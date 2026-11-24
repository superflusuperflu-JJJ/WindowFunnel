import Foundation

// Chromium's SNSS v3 session file associates each tab with a session-storage
// namespace that Chrome carries through restore. Never use a URL as identity.
struct ChromeSessionIndex {
    struct Tab: Hashable { let window: Int32; let id: Int32 }
    var live: [Tab: String] = [:]
    var closed: [Tab: String] = [:]

    init() {}
    init(data: Data) {
        guard data.starts(with: [83, 78, 83, 83, 3, 0, 0, 0]) else { return }
        var windows: [Int32: Int32] = [:], names: [Int32: String] = [:]
        var removed = Set<Int32>()
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func integer(_ offset: Int) -> Int32 {
                Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self))
            }
            var offset = 8
            while offset + 3 <= bytes.count {
                let length = Int(bytes[offset]) + 256 * Int(bytes[offset+1])
                let body = offset + 3
                guard length > 0, offset + 2 + length <= bytes.count else { break }
                switch bytes[offset+2] {
                case 0 where length == 9:
                    windows[integer(body+4)] = integer(body)
                case 19 where length == 49 && integer(body) == 44 && integer(body+8) == 36:
                    let token = String(decoding: bytes[body+12..<body+48], as: UTF8.self)
                    if let uuid = UUID(uuidString: token.replacingOccurrences(of: "_", with: "-")) {
                        names[integer(body+4)] = "restored-" + uuid.uuidString
                    }
                case 16 where length == 17:
                    removed.insert(integer(body))
                default: break
                }
                offset += 2 + length
            }
        }
        for (id, name) in names {
            guard let window = windows[id] else { continue }
            let tab = Tab(window: window, id: id)
            if removed.contains(id) { closed[tab] = name } else { live[tab] = name }
        }
    }
}

// Used only on the serialized Chrome discovery queue. Parse a profile again
// only after Chrome appends to or rotates its current session file.
final class ChromeSessionReader {
    private var cache: [URL: (Date, Int, ChromeSessionIndex)] = [:]
    func read() -> [ChromeSessionIndex] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        let profiles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var active = Set<URL>()
        var result: [ChromeSessionIndex] = []
        for profile in profiles where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
            let dir = profile.appendingPathComponent("Sessions")
            guard let file = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter({ $0.lastPathComponent.hasPrefix("Session_") }).max(by: { $0.lastPathComponent < $1.lastPathComponent }),
                  let info = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = info.contentModificationDate, let size = info.fileSize else { continue }
            active.insert(file)
            if let entry = cache[file], entry.0 == date, entry.1 == size { result.append(entry.2); continue }
            guard let data = try? Data(contentsOf: file) else { continue }
            let index = ChromeSessionIndex(data: data)
            cache[file] = (date, size, index)
            result.append(index)
        }
        cache = cache.filter { active.contains($0.key) }
        return result
    }
}
