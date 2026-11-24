import AppKit
import ImageIO
import UniformTypeIdentifiers
import OSLog

// Chrome tab IDs survive moves between windows, but are scoped to a browser session.
final class TabPreviewStore {
    private let directory: URL
    private let queue = DispatchQueue(label: "local.windowfunnel.tab-files", qos: .utility)
    private let memory = NSCache<NSString, NSImage>()
    private let log = Logger(subsystem: "local.windowfunnel.spike", category: "tab-files")

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WindowFunnel/TabPreviews", isDirectory: true)) {
        self.directory = directory
        memory.countLimit = 24
    }

    func finishPendingWrites() { queue.sync {} }

    private func folder(_ key: String) -> URL {
        key.hasPrefix("restored-") ? directory.appendingPathComponent("Restored", isDirectory: true) : directory
    }

    func image(_ key: String) -> NSImage? {
        if let image = memory.object(forKey: key as NSString) { return image }
        for ext in ["png", "jpg"] {
            let url = folder(key).appendingPathComponent(key + "." + ext)
            if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                memory.setObject(image, forKey: key as NSString)
                return image
            }
        }
        return nil
    }

    func save(_ image: NSImage, key: String) {
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let dpiX = 72 * CGFloat(bitmap.width) / max(1, image.size.width)
        let dpiY = 72 * CGFloat(bitmap.height) / max(1, image.size.height)
        memory.setObject(image, forKey: key as NSString)
        queue.async {
            do {
                var dir = self.folder(key)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try dir.setResourceValues(values)
                let data = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(dest, bitmap, [kCGImagePropertyDPIWidth: dpiX, kCGImagePropertyDPIHeight: dpiY] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { return }
                try (data as Data).write(to: dir.appendingPathComponent(key + ".png"), options: .atomic)
                let old = dir.appendingPathComponent(key + ".jpg")
                if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
            } catch { self.log.error("Could not save tab preview: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func migrate(_ legacy: String, to key: String) {
        queue.async {
            let fm = FileManager.default
            let formats = ["png", "jpg"]
            guard let ext = formats.first(where: { fm.fileExists(atPath: self.folder(legacy).appendingPathComponent(legacy + "." + $0).path) }) else { return }
            do {
                try fm.createDirectory(at: self.folder(key), withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                let existingPNG = self.folder(key).appendingPathComponent(key + ".png")
                let new = self.folder(key).appendingPathComponent(key + "." + ext)
                let old = self.folder(legacy).appendingPathComponent(legacy + "." + ext)
                if !fm.fileExists(atPath: new.path), !fm.fileExists(atPath: existingPNG.path) {
                    try fm.moveItem(at: old, to: new)
                }
                for format in formats {
                    let source = self.folder(legacy).appendingPathComponent(legacy + "." + format)
                    if fm.fileExists(atPath: source.path) { try fm.removeItem(at: source) }
                }
                let oldJPEG = self.folder(key).appendingPathComponent(key + ".jpg")
                if fm.fileExists(atPath: existingPNG.path), fm.fileExists(atPath: oldJPEG.path) {
                    try fm.removeItem(at: oldJPEG)
                }
                self.memory.removeObject(forKey: legacy as NSString)
            } catch { self.log.error("Could not migrate tab preview: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func remove(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        queue.async {
            for key in keys {
                for ext in ["png", "jpg"] {
                    let file = self.folder(key).appendingPathComponent(key + "." + ext)
                    do { try FileManager.default.removeItem(at: file) }
                    catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { }
                    catch { self.log.error("Could not remove closed tab preview: \(error.localizedDescription, privacy: .public)") }
                }
                self.memory.removeObject(forKey: key as NSString)
            }
        }
    }
}
