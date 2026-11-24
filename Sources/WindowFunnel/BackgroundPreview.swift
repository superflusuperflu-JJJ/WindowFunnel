import AppKit

struct BrowserSample: Decodable {
    let tab: Int
    let window: Int
    let url: String
    let jpeg: String?
}

final class BackgroundPreview {
    static let origin = "chrome-extension://jiipjmcjpefgifcnkpiacpjbinmpkmhd/"
    private static let portName = "local.windowfunnel.background-preview.v1" as CFString
    var receive: ((BrowserSample) -> Bool)?
    private var port: CFMessagePort?

    func start() {
        guard port == nil else { return }
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        port = CFMessagePortCreateLocal(nil, Self.portName, { _, _, data, raw in
            let owner = Unmanaged<BackgroundPreview>.fromOpaque(raw!).takeUnretainedValue()
            var ok = false
            if let bytes = data as Data?, bytes.count < 2_000_000,
               let sample = try? JSONDecoder().decode(BrowserSample.self, from: bytes) {
                ok = owner.receive?(sample) == true
            }
            return Unmanaged.passRetained(Data((ok ? "{\"ok\":true}" : "{\"ok\":false}").utf8) as CFData)
        }, &context, nil)
        if let port { CFMessagePortSetDispatchQueue(port, .main) }
    }

    // Chrome starts this executable with the caller's extension origin as argv[1].
    static func relay() {
        let input = FileHandle.standardInput
        func read(_ length: Int) -> Data? {
            var bytes = Data()
            while bytes.count < length {
                let chunk = input.readData(ofLength: length - bytes.count)
                if chunk.isEmpty { return nil }
                bytes.append(chunk)
            }
            return bytes
        }
        guard let header = read(4) else { return }
        let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard length > 0, length < 2_000_000, let payload = read(length) else { return }
        var response: Unmanaged<CFData>?
        if let port = CFMessagePortCreateRemote(nil, portName) {
            CFMessagePortSendRequest(port, 1, payload as CFData, 1, 2, CFRunLoopMode.defaultMode.rawValue, &response)
        }
        let body = response?.takeRetainedValue() as Data? ?? Data("{\"ok\":false}".utf8)
        var count = UInt32(body.count).littleEndian
        FileHandle.standardOutput.write(Data(bytes: &count, count: 4) + body)
    }
}
