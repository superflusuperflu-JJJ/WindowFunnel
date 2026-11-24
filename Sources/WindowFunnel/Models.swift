import AppKit
import ApplicationServices
import FunnelCore

struct WindowItem: Identifiable {
    let number: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let bundleID: String
    let frame: CGRect
    let element: AXUIElement?
    let icon: NSImage?
    var chromeWindowID: String? = nil
    var id: String { chromeWindowID.map { "chrome-\(pid)-\($0)" } ?? String(number) }
    var previewIdentity: PreviewIdentity {
        PreviewIdentity(windowID: number, processID: pid, title: title, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }
}

struct WindowPreview {
    let identity: PreviewIdentity
    let image: NSImage
    let capturedAt: Date
    func image(for window: WindowItem) -> NSImage? {
        PreviewPolicy.canUse(captured: identity, current: window.previewIdentity, age: Date().timeIntervalSince(capturedAt)) ? image : nil
    }
}

struct ChromeTab: Identifiable {
    let id: String
    let title: String
    let url: String
}

struct ChromeWindow {
    let id: String
    let title: String
    let activeTabID: String?
    let tabs: [ChromeTab]
    let frame: CGRect
}

func identity(id: String, title: String, frame: CGRect) -> WindowIdentity {
    WindowIdentity(id: id, title: title, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
}

struct ChromeSnapshot {
    var pid: pid_t? = nil
    var windows: [ChromeWindow] = []
    var error: String?
}

enum NativeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let rawPosition = axValue(element, kAXPositionAttribute),
          let rawSize = axValue(element, kAXSizeAttribute),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
