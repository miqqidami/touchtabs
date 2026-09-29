.PHONY: app install run demo preview icons extension-zip clean

app:
	./scripts/build-app.sh

run: app
	open build/TouchTabs.app

# Installs to /Applications and starts it; it adds itself as a login item on
# first launch so it's always there when Chrome is.
install: app
	-osascript -e 'quit app "TouchTabs"' 2>/dev/null; sleep 1
	rm -rf /Applications/TouchTabs.app
	cp -R build/TouchTabs.app /Applications/
	open /Applications/TouchTabs.app

# Shows sample tabs on the Touch Bar without a browser.
demo:
	cd app && swift run TouchTabs --demo

preview:
	cd app && swift run TouchTabs --render-preview ../docs/preview.png

# Regenerates the extension icons from the vector artwork.
icons:
	cd app && swift build && tmp=$$(mktemp -d) && .build/debug/TouchTabs --render-icons $$tmp && \
		cp $$tmp/icon16.png $$tmp/icon32.png $$tmp/icon48.png $$tmp/icon128.png ../extension/icons/ && rm -rf $$tmp

extension-zip:
	mkdir -p build && rm -f build/touchtabs-extension.zip
	cd extension && zip -qr ../build/touchtabs-extension.zip . -x '.*'

clean:
	rm -rf build app/.build
