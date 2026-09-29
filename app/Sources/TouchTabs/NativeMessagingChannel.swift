import Foundation

/// Chrome native messaging over stdin/stdout: each message is a 32-bit
/// native-endian length followed by that many bytes of UTF-8 JSON.
/// https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
final class NativeMessagingChannel {
    var onMessage: ((Data) -> Void)?
    /// Chrome closed the port (the extension disconnected or the browser quit).
    var onClose: (() -> Void)?

    private let writeQueue = DispatchQueue(label: "io.github.miqqidami.touchtabs.stdout")

    func start() {
        Thread.detachNewThread { [weak self] in
            let input = FileHandle.standardInput
            while let header = Self.read(input, count: 4) {
                let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
                guard length > 0, length < 64 << 20, let body = Self.read(input, count: Int(length)) else { break }
                DispatchQueue.main.async { self?.onMessage?(body) }
            }
            DispatchQueue.main.async { self?.onClose?() }
        }
    }

    func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var length = UInt32(body.count).littleEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(body)
        writeQueue.async {
            FileHandle.standardOutput.write(packet)
        }
    }

    private static func read(_ handle: FileHandle, count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            let chunk = handle.readData(ofLength: count - data.count)
            if chunk.isEmpty { return nil } // EOF
            data.append(chunk)
        }
        return data
    }
}
