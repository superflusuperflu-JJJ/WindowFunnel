import AppKit

enum ShortcutAction { case begin, step(Int), release, cancel, interrupted }

final class ShortcutTap {
    var onAction: ((ShortcutAction) -> Void)?
    // Port lifecycle is owned by the main thread. Only routing state is shared
    // with the input thread; no AX lookup or UI work runs under this lock.
    private let lock = NSLock()
    private var eligible = false
    private var open = false
    private var generation = 0
    var canBegin: Bool {
        get { lock.withLock { eligible } }
        set { lock.withLock { eligible = newValue } }
    }
    var sessionOpen: Bool {
        get { lock.withLock { open } }
        set { lock.withLock { open = newValue } }
    }
    private var port: CFMachPort?
    private var inputLoop: CFRunLoop?
    private var swallowedKeys: Set<Int64> = []
    var running: Bool {
        guard let port, CFMachPortIsValid(port) else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    func start() -> Bool {
        if running { return true }
        stop()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ShortcutTap>.fromOpaque(context).takeUnretainedValue()
            return owner.handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        lock.withLock { port = tap }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            self.lock.withLock { self.inputLoop = loop }
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "WindowFunnel shortcut input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        CGEvent.tapEnable(tap: tap, enable: true)
        if running { return true }
        stop()
        return false
    }

    func stop() {
        let old = lock.withLock { () -> CFMachPort? in
            generation &+= 1
            open = false
            swallowedKeys.removeAll()
            defer { port = nil }
            return port
        }
        if let old { CFMachPortInvalidate(old) }
        if let inputLoop { CFRunLoopStop(inputLoop); CFRunLoopWakeUp(inputLoop) }
        lock.withLock { inputLoop = nil }
    }

    // Called with lock held. Ignore delayed actions from a stopped installation.
    private func send(_ action: ShortcutAction) {
        let version = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.generation == version }) else { return }
            self.onAction?(action)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        defer { lock.unlock() }
        guard port != nil, CFRunLoopGetCurrent() == inputLoop else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            open = false
            swallowedKeys = []
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            send(.interrupted)
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if open && !event.flags.contains(.maskCommand) { send(.release) }
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return swallowedKeys.remove(key) != nil ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let commandTab = key == 48 && flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        if commandTab && (open || eligible) {
            if !open { open = true; send(.begin) }
            else { send(.step(flags.contains(.maskShift) ? -1 : 1)) }
            swallowedKeys.insert(key)
            return nil
        }
        if open {
            if key == 53 { send(.cancel); swallowedKeys.insert(key); return nil }
            if key == 123 || key == 124 { send(.step(key == 123 ? -1 : 1)); swallowedKeys.insert(key); return nil }
            if key == 48 { send(.step(flags.contains(.maskShift) ? -1 : 1)); swallowedKeys.insert(key); return nil }
        }
        return Unmanaged.passUnretained(event)
    }
}
