import AppKit
import ApplicationServices

final class WindowFocusObserver {
    var onChange: (() -> Void)?
    var onChromeTabChange: (() -> Void)?
    private var observer: AXObserver?
    private var source: CFRunLoopSource?
    private var pid: pid_t?

    func watch(_ pid: pid_t?) {
        guard pid != self.pid else { return }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; observer = nil; self.pid = nil
        guard let pid, AXIsProcessTrusted() else { return }
        var created: AXObserver?
        let result = AXObserverCreate(pid, { _, _, name, context in
            guard let context else { return }
            let owner = Unmanaged<WindowFocusObserver>.fromOpaque(context).takeUnretainedValue()
            let tabHint = name as String == kAXTitleChangedNotification || name as String == kAXSelectedChildrenChangedNotification
            DispatchQueue.main.async { [weak owner] in
                if tabHint { owner?.onChromeTabChange?() } else { owner?.onChange?() }
            }
        }, &created)
        guard result == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, context)
        AXObserverAddNotification(created, app, kAXWindowCreatedNotification as CFString, context)
        if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.google.Chrome" {
            AXObserverAddNotification(created, app, kAXTitleChangedNotification as CFString, context)
            AXObserverAddNotification(created, app, kAXSelectedChildrenChangedNotification as CFString, context)
        }
        observer = created
        self.pid = pid
        source = AXObserverGetRunLoopSource(created)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) } }
}
