import AppKit
import ApplicationServices
import ScreenCaptureKit
import FunnelCore

enum WindowService {
    static func scan(onlyPID: pid_t? = nil) -> [WindowItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var axByPID: [pid_t: [AXUIElement]] = [:]
        var mappingByPID: [pid_t: [String: String]] = [:]
        var results: [WindowItem] = []
        for row in rows {
            guard let pid = row[kCGWindowOwnerPID as String] as? Int32, pid != ownPID, onlyPID == nil || pid == onlyPID,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let layer = row[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = row[kCGWindowNumber as String] as? UInt32,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 100, frame.height > 70 else { continue }
            if axByPID[pid] == nil {
                let root = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(root, 0.15)
                axByPID[pid] = AXIsProcessTrusted() ? (axValue(root, kAXWindowsAttribute) as? [AXUIElement] ?? []) : []
                let native = rows.compactMap { candidate -> WindowIdentity? in
                    guard candidate[kCGWindowOwnerPID as String] as? Int32 == pid,
                          candidate[kCGWindowLayer as String] as? Int == 0,
                          let n = candidate[kCGWindowNumber as String] as? UInt32,
                          let raw = candidate[kCGWindowBounds as String] as? [String: Any],
                          let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return nil }
                    return identity(id: String(n), title: candidate[kCGWindowName as String] as? String ?? "", frame: rect)
                }
                let foreign = (axByPID[pid] ?? []).enumerated().compactMap { index, e -> WindowIdentity? in
                    guard let rect = axFrame(e) else { return nil }
                    return identity(id: String(index), title: axValue(e, kAXTitleAttribute) as? String ?? "", frame: rect)
                }
                mappingByPID[pid] = IdentityMatcher.uniqueMapping(native: native, foreign: foreign, allowUniqueGeometryFallback: true)
            }
            let elements = axByPID[pid] ?? []
            let title = row[kCGWindowName as String] as? String ?? ""
            // Reject ambiguity in both directions; never reuse one AX window for duplicate native windows.
            let matchedIndex = mappingByPID[pid]?[String(number)].flatMap(Int.init)
            let element = matchedIndex.flatMap { elements.indices.contains($0) ? elements[$0] : nil }
            guard let element else { continue }
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            guard WindowPolicy.isMainWindow(role: axValue(element, kAXRoleAttribute) as? String,
                subrole: axValue(element, kAXSubroleAttribute) as? String, uniquelyMatched: true,
                supportsRaise: (actions as? [String])?.contains(kAXRaiseAction) == true) else { continue }
            let accessibilityTitle = axValue(element, kAXTitleAttribute) as? String ?? ""
            let resolved = accessibilityTitle.isEmpty ? title : accessibilityTitle
            results.append(WindowItem(number: number, pid: pid, title: resolved.isEmpty ? (app.localizedName ?? "窗口") : resolved,
                appName: app.localizedName ?? "应用", bundleID: app.bundleIdentifier ?? "", frame: frame, element: element, icon: app.icon))
        }
        return results
    }

    static func focusedID(in windows: [WindowItem], pid: pid_t?) -> String? {
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        if let raw = axValue(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let focused = unsafeBitCast(raw, to: AXUIElement.self)
            if let match = windows.first(where: { $0.pid == pid && $0.element.map { CFEqual($0, focused) } == true }) { return match.id }
            return nil
        }
        let candidates = windows.filter { $0.pid == pid }
        return candidates.count == 1 ? candidates.first?.id : nil
    }

    static func activate(_ window: WindowItem) throws {
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            throw NativeError.message("这个应用已关闭，请重新打开总览。")
        }
        // The row may have been scanned on another Space or before the AX window existed.
        func resolveElement() -> AXUIElement? {
            scan(onlyPID: window.pid).first { $0.number == window.number }?.element
        }
        guard var element = window.element ?? resolveElement() else {
            throw NativeError.message("暂时无法定位这个具体窗口。请检查辅助功能权限，或重新刷新窗口。")
        }
        if (axValue(element, kAXMinimizedAttribute) as? Bool) == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        var raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if raised == .invalidUIElement, let fresh = resolveElement() {
            element = fresh
            raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        guard raised == .success else { throw NativeError.message("窗口暂时无法置前（\(raised.rawValue)）。它可能已经关闭或位于其他桌面。") }
        guard app.activate(options: []) || app.isActive else {
            throw NativeError.message("系统暂时无法将这个应用切到前台，请重新打开总览再试。")
        }
        // A second raise after activation prevents the app's other window from covering the target.
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func images(for windows: [WindowItem]) async -> [String: WindowPreview] {
        guard CGPreflightScreenCaptureAccess(), let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return [:] }
        var result: [String: WindowPreview] = [:]
        let available = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        for window in windows {
            guard let source = available[window.number], source.owningApplication?.processID == window.pid, source.windowLayer == 0,
                IdentityMatcher.uniqueMapping(native: [identity(id: window.id, title: window.title, frame: window.frame)],
                    foreign: [identity(id: window.id, title: source.title ?? "", frame: source.frame)], allowUniqueGeometryFallback: true)[window.id] != nil else { continue }
            let config = SCStreamConfiguration()
            let filter = SCContentFilter(desktopIndependentWindow: source)
            // Keep ordinary display-sized windows at native resolution so the card
            // renderer usually does the only downsample. Bound very large surfaces.
            let scale = min(max(1, CGFloat(filter.pointPixelScale)),
                            3072 / max(source.frame.width, source.frame.height, 1),
                            sqrt(4_000_000 / max(1, source.frame.width * source.frame.height)))
            config.captureResolution = .best
            config.width = max(1, Int((source.frame.width * scale).rounded()))
            config.height = max(1, Int((source.frame.height * scale).rounded()))
            config.scalesToFit = true
            config.ignoreShadowsSingleWindow = true
            config.ignoreGlobalClipSingleWindow = true
            config.showsCursor = false
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
            result[window.id] = WindowPreview(identity: window.previewIdentity, image: NSImage(cgImage: image, size: source.frame.size), capturedAt: Date())
        }
        return result
    }
}
