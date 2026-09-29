import AppKit

/// Draws a Chrome-style tab strip sized for the Touch Bar and turns touches
/// into tab actions. Tabs shrink like Chrome's do; once they hit their minimum
/// width the strip scrolls horizontally (with momentum).
final class TabStripView: NSView {
    var onActivate: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onToggleGroup: ((Int) -> Void)?

    /// Shown instead of tabs when there is nothing to draw.
    var placeholder = "Waiting for the TouchTabs browser extension…" {
        didSet { needsDisplay = true }
    }

    private enum Element {
        case tab(TabInfo, GroupInfo?)
        case groupChip(GroupInfo)
        case newTab
    }

    private struct Item {
        let element: Element
        let frame: CGRect
    }

    private enum Metrics {
        static let height: CGFloat = 30
        static let topInset: CGFloat = 2
        static let leading: CGFloat = 8
        static let trailing: CGFloat = 4
        static let pinnedWidth: CGFloat = 42
        static let minTabWidth: CGFloat = 96
        static let maxTabWidth: CGFloat = 190
        static let narrowTabWidth: CGFloat = 64
        static let newTabWidth: CGFloat = 36
        static let cornerRadius: CGFloat = 8
        static let footRadius: CGFloat = 6
        static let iconSize: CGFloat = 16
        static let chipHeight: CGFloat = 20
        static let chipMargin: CGFloat = 5
        static let chipMaxWidth: CGFloat = 140
        static let closeHitWidth: CGFloat = 38
        static let edgeFade: CGFloat = 22
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13)
    private static let chipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    private var state: WindowState?
    private var favicons: [String: NSImage] = [:]
    private var items: [Item] = []
    private var contentWidth: CGFloat = 0
    private var offset: CGFloat = 0 {
        didSet { if offset != oldValue { needsDisplay = true } }
    }
    private var maxOffset: CGFloat { max(0, contentWidth - bounds.width) }

    private var trackedTouch: (NSCopying & NSObjectProtocol)?
    private var touchStartX: CGFloat = 0
    private var offsetAtTouchStart: CGFloat = 0
    private var lastTouchX: CGFloat = 0
    private var lastTouchTime: TimeInterval = 0
    private var velocity: CGFloat = 0
    private var isDragging = false
    private var pressedIndex: Int? {
        didSet { if pressedIndex != oldValue { needsDisplay = true } }
    }
    private var momentumTimer: Timer?
    private var lastMomentumTick: CFTimeInterval = 0

    private var throbberTimer: Timer?
    private var throbberAngle: CGFloat = 90

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.direct]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.height)
    }

    // MARK: - State

    func update(state newState: WindowState?, favicons newFavicons: [String: NSImage]) {
        let previousActive = activeTabID
        let hadState = state != nil
        state = newState
        favicons = newFavicons
        if trackedTouch == nil { pressedIndex = nil }
        relayout()
        if !hadState || activeTabID != previousActive { revealActiveTab() }
        updateThrobberTimer()
        needsDisplay = true
    }

    private var activeTabID: Int? { state?.tabs.first(where: \.active)?.id }

    /// Called when the system takes the strip off the Touch Bar (e.g. the
    /// user tapped the close box).
    var onDetach: (() -> Void)?

    private lazy var widthConstraint: NSLayoutConstraint = {
        let constraint = widthAnchor.constraint(equalToConstant: 1085)
        constraint.isActive = true
        return constraint
    }()

    /// Pins the width to the room the Touch Bar actually gives us. Without an
    /// explicit width the item is laid out at full size and clipped by the
    /// Control Strip, so measure from our origin to the edge of the bar.
    func fitToTouchBar() {
        _ = widthConstraint
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let window else { return }
        let available = floor(window.frame.width - convert(CGPoint.zero, to: nil).x)
        if available > 60, abs(widthConstraint.constant - available) > 0.5 {
            widthConstraint.constant = available
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onDetach?() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
        revealActiveTab()
        needsDisplay = true
    }

    // MARK: - Layout

    private func relayout() {
        items = []
        guard let state else {
            contentWidth = 0
            offset = 0
            return
        }

        var groups: [Int: GroupInfo] = [:]
        for group in state.groups { groups[group.id] = group }

        var elements: [Element] = []
        var previousGroupID = -1
        for tab in state.tabs {
            let group = tab.groupId >= 0 ? groups[tab.groupId] : nil
            if let group, group.id != previousGroupID { elements.append(.groupChip(group)) }
            previousGroupID = group?.id ?? -1
            if group?.collapsed == true { continue }
            elements.append(.tab(tab, group))
        }
        elements.append(.newTab)

        // Like Chrome: fixed-width pieces first, the rest is shared by normal tabs.
        var fixedWidth = Metrics.leading + Metrics.trailing
        var flexibleCount = 0
        for element in elements {
            switch element {
            case .tab(let tab, _):
                if tab.pinned { fixedWidth += Metrics.pinnedWidth } else { flexibleCount += 1 }
            case .groupChip(let group): fixedWidth += chipWidth(group)
            case .newTab: fixedWidth += Metrics.newTabWidth
            }
        }
        let shared = flexibleCount > 0 ? (bounds.width - fixedWidth) / CGFloat(flexibleCount) : 0
        let tabWidth = floor(min(max(shared, Metrics.minTabWidth), Metrics.maxTabWidth))

        var x = Metrics.leading
        for element in elements {
            let width: CGFloat
            switch element {
            case .tab(let tab, _): width = tab.pinned ? Metrics.pinnedWidth : tabWidth
            case .groupChip(let group): width = chipWidth(group)
            case .newTab: width = Metrics.newTabWidth
            }
            items.append(Item(element: element, frame: CGRect(x: x, y: 0, width: width, height: bounds.height)))
            x += width
        }
        contentWidth = x + Metrics.trailing
        offset = min(max(offset, 0), maxOffset)
    }

    private func chipWidth(_ group: GroupInfo) -> CGFloat {
        if group.title.isEmpty { return 26 }
        let text = (group.title as NSString).size(withAttributes: [.font: Self.chipFont]).width
        return min(ceil(text) + 16, Metrics.chipMaxWidth) + Metrics.chipMargin * 2
    }

    private func revealActiveTab() {
        guard trackedTouch == nil, momentumTimer == nil,
              let frame = items.first(where: { item in
                  if case .tab(let tab, _) = item.element { return tab.active }
                  return false
              })?.frame
        else { return }
        let margin: CGFloat = 28
        if frame.minX - margin < offset {
            offset = max(0, frame.minX - margin)
        } else if frame.maxX + margin > offset + bounds.width {
            offset = min(maxOffset, frame.maxX + margin - bounds.width)
        }
    }

    // MARK: - Drawing

    private var contentMidY: CGFloat { (bounds.height - Metrics.topInset) / 2 }

    override func draw(_ dirtyRect: NSRect) {
        let clip = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        Theme.frame.setFill()
        clip.fill()

        guard state != nil else {
            drawPlaceholder()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: -offset, yBy: 0)
        transform.concat()

        drawSeparators()
        for (index, item) in items.enumerated() {
            guard case .tab(let tab, let group) = item.element else { continue }
            if tab.active {
                drawTabBackground(item.frame, color: Theme.activeTab, outline: group.map { Theme.groupColor($0.color) })
            } else if index == pressedIndex {
                drawTabBackground(item.frame, color: Theme.pressedTab, outline: nil)
            }
        }
        drawGroupUnderlines()
        for (index, item) in items.enumerated() {
            switch item.element {
            case .tab(let tab, _):
                let background = tab.active ? Theme.activeTab : (index == pressedIndex ? Theme.pressedTab : Theme.frame)
                drawTabContents(tab, in: item.frame, background: background)
            case .groupChip(let group):
                drawChip(group, in: item.frame, pressed: index == pressedIndex)
            case .newTab:
                drawNewTabButton(in: item.frame, pressed: index == pressedIndex)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawEdgeFades(clip: clip)
    }

    private func drawPlaceholder() {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: Theme.inactiveTitle]
        let size = (placeholder as NSString).size(withAttributes: attrs)
        (placeholder as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                       withAttributes: attrs)
    }

    private func drawTabBackground(_ frame: CGRect, color: NSColor, outline: NSColor?) {
        let body = CGRect(x: frame.minX, y: 0, width: frame.width, height: bounds.height - Metrics.topInset)
        let path = Artwork.tabPath(body: body, cornerRadius: Metrics.cornerRadius, footRadius: Metrics.footRadius)
        color.setFill()
        path.fill()
        if let outline {
            // Chrome outlines the active tab of a group in the group's color.
            outline.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawSeparators() {
        Theme.separator.setFill()
        for index in items.indices.dropLast() {
            guard case .tab(let left, _) = items[index].element,
                  case .tab(let right, _) = items[index + 1].element,
                  !left.active, !right.active,
                  pressedIndex != index, pressedIndex != index + 1
            else { continue }
            let x = items[index].frame.maxX
            CGRect(x: x - 0.5, y: contentMidY - 8, width: 1, height: 16).fill()
        }
    }

    private func drawGroupUnderlines() {
        var index = 0
        while index < items.count {
            guard case .groupChip(let group) = items[index].element, !group.collapsed else {
                index += 1
                continue
            }
            var last = index
            while last + 1 < items.count, case .tab(_, let g) = items[last + 1].element, g?.id == group.id {
                last += 1
            }
            if last > index {
                let startX = items[index].frame.minX + Metrics.chipMargin
                let endX = items[last].frame.maxX - Metrics.chipMargin
                Theme.groupColor(group.color).setFill()
                NSBezierPath(roundedRect: CGRect(x: startX, y: 0.5, width: endX - startX, height: 2.5),
                             xRadius: 1.25, yRadius: 1.25).fill()
            }
            index = last + 1
        }
    }

    private func drawTabContents(_ tab: TabInfo, in frame: CGRect, background: NSColor) {
        let midY = contentMidY
        let iconRect = { (x: CGFloat) in
            CGRect(x: x, y: midY - Metrics.iconSize / 2, width: Metrics.iconSize, height: Metrics.iconSize)
        }

        if tab.pinned {
            drawFavicon(for: tab, in: iconRect(frame.midX - Metrics.iconSize / 2))
            return
        }

        let isNarrow = frame.width < Metrics.narrowTabWidth
        if isNarrow {
            // Chrome shows only the close button on a narrow active tab.
            if tab.active {
                drawCloseGlyph(in: iconRect(frame.midX - Metrics.iconSize / 2))
            } else {
                drawFavicon(for: tab, in: iconRect(frame.midX - Metrics.iconSize / 2))
            }
            return
        }

        var left = frame.minX + 12
        var right = frame.maxX - 10
        drawFavicon(for: tab, in: iconRect(left))
        left += Metrics.iconSize + 8

        if tab.active {
            let close = iconRect(right - Metrics.iconSize)
            drawCloseGlyph(in: close)
            right = close.minX - 4
        }
        if tab.audible || tab.muted, right - left > Metrics.iconSize + 12 {
            let audio = iconRect(right - Metrics.iconSize)
            let name = tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            if let glyph = Glyph.symbol(name, pointSize: 11, color: tab.active ? Theme.activeTitle : Theme.inactiveTitle) {
                drawCentered(glyph, in: audio)
            }
            right = audio.minX - 4
        }
        if right - left > 8 {
            let rect = CGRect(x: left, y: 0, width: right - left, height: bounds.height - Metrics.topInset)
            drawTitle(tab.title, in: rect, color: tab.active ? Theme.activeTitle : Theme.inactiveTitle, background: background)
        }
    }

    private func drawFavicon(for tab: TabInfo, in rect: CGRect) {
        if tab.loading {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: CGPoint(x: rect.midX, y: rect.midY), radius: 6.5,
                          startAngle: throbberAngle, endAngle: throbberAngle - 270, clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            Theme.throbber.setStroke()
            arc.stroke()
            return
        }
        if let key = tab.favicon, let image = favicons[key] {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        } else if let globe = Glyph.symbol("globe", pointSize: 13, color: Theme.inactiveTitle) {
            drawCentered(globe, in: rect)
        }
    }

    private func drawCloseGlyph(in rect: CGRect) {
        let arm: CGFloat = 4
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x - arm, y: c.y - arm)); path.line(to: CGPoint(x: c.x + arm, y: c.y + arm))
        path.move(to: CGPoint(x: c.x - arm, y: c.y + arm)); path.line(to: CGPoint(x: c.x + arm, y: c.y - arm))
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        Theme.activeTitle.setStroke()
        path.stroke()
    }

    private func drawTitle(_ title: String, in rect: CGRect, color: NSColor, background: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: color]
        let text = title.replacingOccurrences(of: "\n", with: " ") as NSString
        let size = text.size(withAttributes: attrs)
        let line = CGRect(x: rect.minX, y: rect.midY - size.height / 2, width: rect.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: line).addClip()
        text.draw(at: line.origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        // Chrome fades long titles out instead of truncating with an ellipsis.
        if size.width > rect.width {
            let fade = CGRect(x: line.maxX - 20, y: line.minY, width: 20, height: line.height)
            NSGradient(starting: background.withAlphaComponent(0), ending: background)?.draw(in: fade, angle: 0)
        }
    }

    private func drawChip(_ group: GroupInfo, in frame: CGRect, pressed: Bool) {
        let color = Theme.groupColor(group.color).blended(withFraction: pressed ? 0.25 : 0, of: .black) ?? Theme.groupColor(group.color)
        let midY = contentMidY
        color.setFill()
        if group.title.isEmpty {
            let d: CGFloat = 10
            NSBezierPath(ovalIn: CGRect(x: frame.midX - d / 2, y: midY - d / 2, width: d, height: d)).fill()
            return
        }
        let chip = CGRect(x: frame.minX + Metrics.chipMargin, y: midY - Metrics.chipHeight / 2,
                          width: frame.width - Metrics.chipMargin * 2, height: Metrics.chipHeight)
        NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.chipFont, .foregroundColor: Theme.groupChipText]
        let size = (group.title as NSString).size(withAttributes: attrs)
        let textRect = chip.insetBy(dx: 8, dy: 0)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()
        (group.title as NSString).draw(at: CGPoint(x: max(textRect.minX, chip.midX - size.width / 2), y: chip.midY - size.height / 2),
                                       withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawNewTabButton(in frame: CGRect, pressed: Bool) {
        let c = CGPoint(x: frame.midX, y: contentMidY)
        if pressed {
            Theme.activeTab.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)).fill()
        }
        let arm: CGFloat = 6
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x - arm, y: c.y)); path.line(to: CGPoint(x: c.x + arm, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - arm)); path.line(to: CGPoint(x: c.x, y: c.y + arm))
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        Theme.inactiveTitle.setStroke()
        path.stroke()
    }

    private func drawEdgeFades(clip: NSBezierPath) {
        guard maxOffset > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if offset > 0 {
            NSGradient(starting: Theme.frame, ending: Theme.frame.withAlphaComponent(0))?
                .draw(in: CGRect(x: 0, y: 0, width: Metrics.edgeFade, height: bounds.height), angle: 0)
        }
        if offset < maxOffset {
            NSGradient(starting: Theme.frame.withAlphaComponent(0), ending: Theme.frame)?
                .draw(in: CGRect(x: bounds.width - Metrics.edgeFade, y: 0, width: Metrics.edgeFade, height: bounds.height), angle: 0)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCentered(_ image: NSImage, in rect: CGRect) {
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    // MARK: - Loading indicator

    private func updateThrobberTimer() {
        let loading = state?.tabs.contains(where: \.loading) ?? false
        if loading, throbberTimer == nil {
            throbberTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30, target: self,
                                                 selector: #selector(throbberTick), userInfo: nil, repeats: true)
        } else if !loading {
            throbberTimer?.invalidate()
            throbberTimer = nil
        }
    }

    @objc private func throbberTick() {
        throbberAngle -= 14
        needsDisplay = true
    }

    // MARK: - Touches

    private func itemIndex(atViewX x: CGFloat) -> Int? {
        let contentX = x + offset
        return items.firstIndex { $0.frame.minX <= contentX && contentX < $0.frame.maxX }
    }

    override func touchesBegan(with event: NSEvent) {
        guard trackedTouch == nil, let touch = event.touches(matching: .began, in: self).first else { return }
        stopMomentum()
        let x = touch.location(in: self).x
        trackedTouch = touch.identity
        touchStartX = x
        lastTouchX = x
        lastTouchTime = event.timestamp
        offsetAtTouchStart = offset
        velocity = 0
        isDragging = false
        pressedIndex = itemIndex(atViewX: x)
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = trackedTouchIn(event, phase: .moved) else { return }
        let x = touch.location(in: self).x
        if !isDragging, maxOffset > 0, abs(x - touchStartX) > 6 {
            isDragging = true
            pressedIndex = nil
        }
        if isDragging {
            offset = min(max(offsetAtTouchStart - (x - touchStartX), 0), maxOffset)
            let dt = event.timestamp - lastTouchTime
            if dt > 0 {
                let instant = -(x - lastTouchX) / CGFloat(dt)
                velocity = velocity * 0.4 + instant * 0.6
            }
        }
        lastTouchX = x
        lastTouchTime = event.timestamp
    }

    override func touchesEnded(with event: NSEvent) {
        guard trackedTouchIn(event, phase: .ended) != nil else { return }
        if isDragging {
            if event.timestamp - lastTouchTime > 0.08 { velocity = 0 }
            startMomentum()
        } else {
            performTap(atViewX: touchStartX)
        }
        resetTouch()
    }

    override func touchesCancelled(with event: NSEvent) {
        guard trackedTouchIn(event, phase: .cancelled) != nil else { return }
        resetTouch()
    }

    private func trackedTouchIn(_ event: NSEvent, phase: NSTouch.Phase) -> NSTouch? {
        guard let tracked = trackedTouch else { return nil }
        return event.touches(matching: phase, in: self).first { $0.identity.isEqual(tracked) }
    }

    private func resetTouch() {
        trackedTouch = nil
        isDragging = false
        pressedIndex = nil
    }

    private func performTap(atViewX x: CGFloat) {
        guard let index = itemIndex(atViewX: x) else { return }
        let item = items[index]
        switch item.element {
        case .tab(let tab, _):
            let closeZone = item.frame.width < Metrics.narrowTabWidth
                ? item.frame
                : CGRect(x: item.frame.maxX - Metrics.closeHitWidth, y: 0, width: Metrics.closeHitWidth, height: bounds.height)
            if tab.active, !tab.pinned, closeZone.contains(CGPoint(x: x + offset, y: 1)) {
                applyLocally { $0.tabs.removeAll { $0.id == tab.id } }
                onClose?(tab.id)
            } else if !tab.active {
                // Update immediately; the extension confirms a few ms later.
                applyLocally { state in
                    for i in state.tabs.indices { state.tabs[i].active = state.tabs[i].id == tab.id }
                }
                onActivate?(tab.id)
            }
        case .groupChip(let group):
            applyLocally { state in
                if let i = state.groups.firstIndex(where: { $0.id == group.id }) { state.groups[i].collapsed.toggle() }
            }
            onToggleGroup?(group.id)
        case .newTab:
            onNewTab?()
        }
    }

    private func applyLocally(_ change: (inout WindowState) -> Void) {
        guard var newState = state else { return }
        change(&newState)
        update(state: newState, favicons: favicons)
    }

    // MARK: - Momentum scrolling

    private func startMomentum() {
        guard abs(velocity) > 60, maxOffset > 0 else { return }
        lastMomentumTick = CACurrentMediaTime()
        momentumTimer = Timer.scheduledTimer(timeInterval: 1.0 / 60, target: self,
                                             selector: #selector(momentumTick), userInfo: nil, repeats: true)
    }

    @objc private func momentumTick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastMomentumTick)
        lastMomentumTick = now
        offset = min(max(offset + velocity * dt, 0), maxOffset)
        velocity *= pow(0.03, dt)
        if abs(velocity) < 20 || offset <= 0 || offset >= maxOffset { stopMomentum() }
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
    }
}
