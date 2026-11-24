import AppKit
import SwiftUI
import FunnelCore
import ApplicationServices

final class Coordinator: ObservableObject {
    @Published var interaction = Interaction()
    private(set) var presentationID = UUID()
    @Published var windows: [WindowItem] = []
    @Published var images: [String: WindowPreview] = [:]
    private let tabFiles = TabPreviewStore()
    private var sampledAt: [String: Date] = [:]

    private let sessionReader = ChromeSessionReader()
    private var stableKeys: [String: String] = [:]

    private func tabKey(_ app: NSRunningApplication?, _ tab: String) -> String? {
        guard let key = legacyTabKey(app, tab) else { return nil }
        return stableKeys[key] ?? key
    }

    private func legacyTabKey(_ app: NSRunningApplication?, _ tab: String) -> String? {
        guard let app, let launch = app.launchDate, let id = Int(tab) else { return nil }
        return "\(app.processIdentifier)-\(Int64(launch.timeIntervalSince1970 * 1000))-\(id)"
    }
    private let backgroundPreview = BackgroundPreview()
    private var capturingTab = false
    private var tabSampleGeneration = 0
    private var firstSample: DispatchWorkItem?
    private var settledSample: DispatchWorkItem?
    private var pendingTabSample = false
    @Published var chrome = ChromeSnapshot()
    @Published var status = "正在准备窗口列表…"
    @Published var accessibility = AXIsProcessTrusted()
    @Published var screenCapture = CGPreflightScreenCaptureAccess()
    @Published var shortcutEnabled = false
    @Published var chromeConnection = ChromeConnection()
    @Published var refreshing = false
    var chromeEnabled: Bool { chromeConnection.enabled }
    var chromeConnecting: Bool { chromeConnection.isConnecting }
    var chromeStatus: String {
        if let error = chromeConnection.error { return error }
        if chromeConnecting { return "正在连接 Chrome…" }
        if let count = chromeConnection.tabCount, chromeConnection.isConnected {
            return count > 0 ? "已连接 · \(count) 个标签页" : "已连接 · 暂无普通标签页，隐私窗口不枚举。"
        }
        return "读取普通窗口的标签页标题和网址，并切换标签页。"
    }
    private(set) var windowLayoutSizes: [CGSize] = []
    private(set) var tabLayoutSizes: [CGSize] = []
    private(set) var sessionWindows: [WindowItem] = []
    private(set) var sessionChrome: [String: ChromeWindow] = [:]
    private let tap = ShortcutTap()
    private let scanQueue = DispatchQueue(label: "local.windowfunnel.discovery", qos: .utility)
    private let chromeQueue = DispatchQueue(label: "local.windowfunnel.chrome", qos: .userInitiated)
    private var panel: OverlayPanel?
    private var timer: Timer?
    private var eventMonitor: Any?
    private var mru: [String] = []
    private var swipe = SwipePaging()
    private var repeatTimer: Timer?
    private var wheelAmount: CGFloat = 0
    @Published private(set) var dragOffset: CGFloat = 0
    private var startingApp: NSRunningApplication?
    private var capturing = false
    private var capturePending = false
    private let focusObserver = WindowFocusObserver()
    private var wakeObservers: [NSObjectProtocol] = []
    private var activationObserver: NSObjectProtocol?
    var onOpenSettings: (() -> Void)?

    var currentWindow: WindowItem? {
        let id = interaction.level == .tabs ? interaction.parentID : interaction.selectedID
        return sessionWindows.first { $0.id == id }
    }
    var visibleTabs: [ChromeTab] {
        guard let id = interaction.parentID else { return [] }
        return sessionChrome[id]?.tabs ?? []
    }
    var selectedTitle: String {
        if interaction.level == .tabs { return visibleTabs.first { $0.id == interaction.selectedID }?.title ?? "标签页" }
        return currentWindow?.title ?? "窗口"
    }

    init() {
        backgroundPreview.receive = { [weak self] sample in self?.receiveBackgroundSample(sample) ?? false }
        backgroundPreview.start()
        tap.onAction = { [weak self] action in self?.handle(action) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            guard let self, self.interaction.level != .closed else { return event }
            if event.type == .scrollWheel { self.scroll(event); return nil }
            // A menu-opened preview also works while the system-wide shortcut is paused.
            // A key swallowed by the global tap never reaches this local monitor.
            if event.keyCode == 53 { self.cancel(); return nil }
            if !self.tap.running {
                if event.keyCode == 123 || event.keyCode == 124 { self.step(event.keyCode == 123 ? -1 : 1); return nil }
                if event.keyCode == 48 && !event.modifierFlags.contains(.command) { self.step(event.modifierFlags.contains(.shift) ? -1 : 1); return nil }
            }
            return event
        }
        focusObserver.onChromeTabChange = { [weak self] in self?.scheduleTabSample() }
        focusObserver.onChange = { [weak self] in self?.rememberCurrentFocus(); self?.scheduleTabSample() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rememberCurrentFocus()
            self?.scheduleTabSample()
        }
        let notifications = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        if UserDefaults.standard.bool(forKey: "restoreChromeConnection") { connectChrome() }
        refresh()
    }

    func finishPendingWrites() { tabFiles.finishPendingWrites() }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenCapture = CGPreflightScreenCaptureAccess()
        if !screenCapture { images.removeAll() }
        if shortcutEnabled {
            if !accessibility {
                stop()
                status = "辅助功能权限不可用，已恢复系统 Command-Tab。"
            } else if !tap.running {
                cancel()
                status = tap.start() ? "Command-Tab 监听已恢复。" : "正在等待系统恢复 Command-Tab 监听…"
            }
        }
        guard !refreshing else { return }
        refreshing = true
        scanQueue.async { [weak self] in
            let native = WindowService.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                let discovered = self.includingDuplicateChromeWindows(native)
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let focused = WindowService.focusedID(in: discovered, pid: frontPID)
                if self.interaction.level == .closed, let focused {
                    self.mru.removeAll { $0 == focused }
                    self.mru.insert(focused, at: 0)
                }
                let alive = Set(discovered.map(\.id))
                self.mru.removeAll { !alive.contains($0) }
                let ranks = Dictionary(self.mru.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                self.windows = discovered.enumerated().sorted {
                    let a = ranks[$0.element.id] ?? (100_000 + $0.offset)
                    let b = ranks[$1.element.id] ?? (100_000 + $1.offset)
                    return a < b
                }.map(\.element)
                let currentByID = Dictionary(self.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                self.images = self.images.filter { entry in
                    guard let window = currentByID[entry.key] else { return false }
                    return entry.value.image(for: window) != nil
                }
                if self.interaction.level != .closed {
                    // Refresh metadata without rearranging the row under the user's pointer.
                    self.sessionWindows = self.sessionWindows.map { currentByID[$0.id] ?? $0 }
                }
                self.tap.canBegin = !self.windows.isEmpty && self.accessibility
                self.focusObserver.watch(frontPID == ProcessInfo.processInfo.processIdentifier ? nil : frontPID)
                if !self.shortcutEnabled { self.status = self.windows.isEmpty ? "暂未找到可切换窗口。请先打开一个普通应用窗口。" : "已找到 \(self.windows.count) 个窗口。开启后可用 Command-Tab。" }
                self.captureSelectedAndRecent()
            }
        }
        if chromeEnabled && !chromeConnection.isRefreshing { refreshChrome() }
    }

    private func rememberCurrentFocus() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        focusObserver.watch(pid)
        guard interaction.level == .closed,
              let id = WindowService.focusedID(in: windows, pid: pid) else { return }
        mru.removeAll { $0 == id }; mru.insert(id, at: 0)
        let rank = Dictionary(mru.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        windows = windows.enumerated().sorted {
            (rank[$0.element.id] ?? (100_000+$0.offset)) < (rank[$1.element.id] ?? (100_000+$1.offset))
        }.map(\.element)
    }

    private func receiveBackgroundSample(_ sample: BrowserSample) -> Bool {
        guard screenCapture, CGPreflightScreenCaptureAccess(), chromeConnection.isConnected,
              let browser = chrome.windows.first(where: { $0.id == String(sample.window) }),
              browser.tabs.contains(where: { $0.id == String(sample.tab) && $0.url == sample.url }),
              let window = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return false }
        guard let key = tabKey(window, String(sample.tab)) else { return false }
        if sample.jpeg == nil { return tabFiles.image(key) == nil }
        guard let jpeg = sample.jpeg, let bytes = Data(base64Encoded: jpeg),
              let bitmap = NSBitmapImageRep(data: bytes), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              max(bitmap.pixelsWide, bitmap.pixelsHigh) <= 1800 else { return false }
        let mapped = matchedChromeWindows(windows, chrome)
        guard let item = windows.first(where: { $0.pid == window.processIdentifier && mapped[$0.id]?.id == browser.id }) else { return false }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        storeTabPreview(WindowPreview(identity: item.previewIdentity, image: image, capturedAt: Date()), for: key)
        return true
    }

    func connectChrome() {
        refreshChrome(userInitiated: true)
    }

    private func refreshChrome(userInitiated: Bool = false) {
        guard chromeConnection.begin(userInitiated: userInitiated) else { return }
        chromeQueue.async { [weak self] in
            let snapshot = ChromeService.snapshot()
            let indices = snapshot.pid == nil ? [] : self?.sessionReader.read() ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                if userInitiated, snapshot.error == nil { UserDefaults.standard.set(true, forKey: "restoreChromeConnection") }
                self.chrome = snapshot
                self.refreshTabPreviews(snapshot, indices: indices)
                self.chromeConnection.finish(tabCount: snapshot.windows.reduce(0) { $0 + $1.tabs.count }, error: snapshot.error)
            }
        }
    }

    // Equal titles and frames cannot identify a Core Graphics surface. Chrome can
    // still identify each real, normal window by its own session ID.
    private func includingDuplicateChromeWindows(_ native: [WindowItem]) -> [WindowItem] {
        guard accessibility, chromeConnection.isConnected,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return native }
        var result = native
        for browser in chrome.windows {
            let duplicates = chrome.windows.filter { $0.title == browser.title && $0.frame.equalTo(browser.frame) }
            guard duplicates.count > 1 else { continue }
            // During a title change the two asynchronous inventories may disagree.
            // Prefer a native card for this group until both observations agree.
            guard !native.contains(where: { $0.pid == app.processIdentifier && $0.frame.equalTo(browser.frame) &&
                ($0.title == browser.title || $0.title == browser.title + " - Google Chrome") }) else { continue }
            result.append(WindowItem(number: 0, pid: app.processIdentifier, title: browser.title,
                appName: app.localizedName ?? "Chrome", bundleID: "com.google.Chrome", frame: browser.frame,
                element: nil, icon: app.icon, chromeWindowID: browser.id))
        }
        return result
    }

    private func matchedChromeWindows(_ sessionWindows: [WindowItem], _ chrome: ChromeSnapshot) -> [String: ChromeWindow] {
        var result: [String: ChromeWindow] = [:]
        let nativeChrome = sessionWindows.filter { $0.bundleID == "com.google.Chrome" }
        let mapping = IdentityMatcher.uniqueMapping(
            native: nativeChrome.map { identity(id: $0.id, title: $0.title, frame: $0.frame) },
            foreign: chrome.windows.map { identity(id: $0.id, title: $0.title, frame: $0.frame) })
        for window in nativeChrome {
            if let id = window.chromeWindowID ?? mapping[window.id], let browser = chrome.windows.first(where: { $0.id == id }) {
                result[window.id] = browser
            }
        }
        return result
    }

    func preview(for window: WindowItem, tab: ChromeTab?) -> NSImage? {
        guard screenCapture else { return nil }
        if tab == nil, window.chromeWindowID == nil { return images[window.id]?.image(for: window) }
        guard let browser = sessionChrome[window.id],
              let tab = tab ?? browser.tabs.first(where: { $0.id == browser.activeTabID }) else { return nil }
        guard let key = tabKey(NSRunningApplication(processIdentifier: window.pid), tab.id) else { return nil }
        return tabFiles.image(key)
    }

    private func scheduleTabSample() {
        tabSampleGeneration += 1
        firstSample?.cancel()
        settledSample?.cancel()
        pendingTabSample = false
        guard chromeConnection.isConnected, screenCapture,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else { return }
        let generation = tabSampleGeneration
        func sample(after delay: Double) -> DispatchWorkItem {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.tabSampleGeneration == generation else { return }
                self.sampleFrontChromeTab()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
        firstSample = sample(after: 0.18)
        settledSample = sample(after: 1.1)
    }

    private func finishTabSample() {
        capturingTab = false
        if pendingTabSample {
            pendingTabSample = false
            sampleFrontChromeTab()
        }
    }

    private func sampleFrontChromeTab() {
        guard chromeConnection.isConnected, screenCapture,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.google.Chrome" else { return }
        guard !capturingTab else { pendingTabSample = true; return }
        capturingTab = true
        let generation = tabSampleGeneration
        let pid = app.processIdentifier
        Task { @MainActor in
            defer { finishTabSample() }
            let (candidates, before) = await withCheckedContinuation { continuation in
                chromeQueue.async {
                    continuation.resume(returning: (WindowService.scan(onlyPID: pid), ChromeService.snapshot(activeOnly: true)))
                }
            }
            guard generation == tabSampleGeneration,
                  let focusedID = WindowService.focusedID(in: candidates, pid: pid),
                  let window = candidates.first(where: { $0.id == focusedID }),
                  let browser = matchedChromeWindows(candidates, before)[focusedID],
                  let tab = browser.tabs.first, tab.id == browser.activeTabID, !tab.url.isEmpty,
                  let shot = await WindowService.images(for: [window])[focusedID] else { return }
            let after = await withCheckedContinuation { continuation in
                chromeQueue.async { continuation.resume(returning: ChromeService.snapshot(activeOnly: true)) }
            }
            guard generation == tabSampleGeneration, CGPreflightScreenCaptureAccess(), chromeConnection.isConnected,
                  let confirmed = matchedChromeWindows(candidates, after)[focusedID], confirmed.id == browser.id,
                  confirmed.activeTabID == tab.id, confirmed.tabs.first?.url == tab.url else { return }
            if let key = tabKey(app, tab.id) { storeTabPreview(shot, for: key) }
        }
    }

    private func storeTabPreview(_ shot: WindowPreview, for key: String) {
        sampledAt[key] = shot.capturedAt
        tabFiles.save(shot.image, key: key)
        objectWillChange.send()
    }

    private func refreshTabPreviews(_ snapshot: ChromeSnapshot, indices: [ChromeSessionIndex]) {
        guard snapshot.error == nil else { return }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
        guard snapshot.pid == app?.processIdentifier, app == nil || app?.launchDate != nil else { return }
        guard let app else { return }
        let liveWindows = Set(snapshot.windows.compactMap { Int32($0.id) })
        let liveIDs = Set(snapshot.windows.flatMap { $0.tabs.compactMap { Int32($0.id) } })
        for window in snapshot.windows {
            guard let windowID = Int32(window.id) else { continue }
            for tab in window.tabs {
                guard let id = Int32(tab.id), let legacy = legacyTabKey(app, tab.id) else { continue }
                let names = Set(indices.compactMap { $0.live[.init(window: windowID, id: id)] })
                if names.count == 1, let name = names.first, stableKeys[legacy] != name {
                    tabFiles.migrate(legacy, to: name)
                    stableKeys[legacy] = name
                }
            }
        }
        // A disappearing window may be Chrome shutting down. Require both an
        // explicit Chrome close record and a still-open containing window.
        let protectedKeys = Set(snapshot.windows.flatMap { $0.tabs.compactMap { tabKey(app, $0.id) } })
        var deleted = Set<String>()
        for index in indices {
            for (tab, name) in index.closed where liveWindows.contains(tab.window) && !liveIDs.contains(tab.id) && !protectedKeys.contains(name) {
                deleted.insert(name)
                if let key = legacyTabKey(app, String(tab.id)) {
                    deleted.insert(key)
                    stableKeys.removeValue(forKey: key)
                }
            }
        }
        tabFiles.remove(deleted)
        sampledAt = sampledAt.filter { protectedKeys.contains($0.key) }
        guard screenCapture, !capturingTab else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let focused = WindowService.focusedID(in: windows, pid: app.processIdentifier) else { return }
        let mapping = matchedChromeWindows(windows, snapshot)
        for window in windows where window.id == focused && window.chromeWindowID == nil {
            guard let browser = mapping[window.id],
                  let tab = browser.tabs.first(where: { $0.id == browser.activeTabID }),
                  !tab.url.isEmpty else { continue }
            guard let key = tabKey(app, tab.id) else { continue }
            if let prior = sampledAt[key], Date().timeIntervalSince(prior) < 3 { continue }
            capturingTab = true
            Task { @MainActor in
                defer { finishTabSample() }
                guard let shot = await WindowService.images(for: [window])[window.id] else { return }
                // Re-read Chrome after capture: a switch or navigation during capture invalidates this sample.
                let after = await withCheckedContinuation { continuation in
                    chromeQueue.async { continuation.resume(returning: ChromeService.snapshot()) }
                }
                guard CGPreflightScreenCaptureAccess(), chromeConnection.isConnected,
                      let current = windows.first(where: { $0.id == window.id }),
                      shot.image(for: current) != nil,
                      let confirmed = matchedChromeWindows(windows, after)[window.id],
                      confirmed.id == browser.id, confirmed.activeTabID == tab.id,
                      confirmed.tabs.contains(where: { $0.id == tab.id && $0.url == tab.url }) else { return }
                if let currentKey = tabKey(app, tab.id) { storeTabPreview(shot, for: currentKey) }
            }
            break
        }
    }

    func start() {
        refresh()
        guard AXIsProcessTrusted() else { status = "请先在系统设置中开启辅助功能，再点“开启 Command-Tab”。"; return }
        guard tap.start() else { status = "系统尚未允许拦截快捷键。请确认辅助功能授权后重启原型。"; return }
        shortcutEnabled = true
        tap.canBegin = !windows.isEmpty
        status = "Command-Tab 已开启。菜单栏中可以随时暂停或退出。"
    }

    func stop() {
        cancel()
        tap.stop()
        shortcutEnabled = false
        status = "已暂停，Command-Tab 使用系统行为。"
    }

    func openPinnedPreview() {
        guard !windows.isEmpty else { status = "还没有可显示的窗口，稍后重试。"; return }
        begin()
        // A menu click has no held Command; latch the first layer for pointer-only exploration.
        if let selected = currentWindow {
            interaction.expand(tabIDs: [selected.id], activeID: selected.id)
            interaction.back()
        }
    }

    private func begin() {
        guard interaction.level == .closed else { return }
        startingApp = NSWorkspace.shared.frontmostApplication
        sessionWindows = windows
        windowLayoutSizes = windows.map { $0.frame.size }
        sessionChrome = matchedChromeWindows(sessionWindows, chrome)
        let current = WindowService.focusedID(in: sessionWindows, pid: startingApp?.processIdentifier)
        presentationID = UUID()
        interaction.begin(windowIDs: sessionWindows.map(\.id), currentID: current)
        guard interaction.level != .closed else { tap.sessionOpen = false; return }
        resetScroll()
        tap.sessionOpen = true
        if panel == nil {
            let created = OverlayPanel()
            created.install(NSHostingView(rootView: OverlayView(coordinator: self)))
            panel = created
        }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        panel?.setFrame(screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
        panel?.presentOverview()
        captureSelectedAndRecent(forceSelected: true)
    }

    private func handle(_ action: ShortcutAction) {
        switch action {
        case .begin: begin()
        case .step(let delta): step(delta)
        case .release: apply(interaction.releaseCommand())
        case .cancel: cancel()
        case .interrupted: cancel(); status = "系统中断了快捷键监听，本次选择已取消，将自动检查并恢复。"
        }
    }

    func step(_ delta: Int) {
        guard interaction.level != .closed else { return }
        if dragOffset != 0 { dragOffset = 0 }
        interaction.step(delta)
        captureSelectedAndRecent(forceSelected: true)
    }

    private func resetScroll() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        swipe = SwipePaging()
        wheelAmount = 0
        if dragOffset != 0 {
            let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.22, bounce: 0)
            withAnimation(animation) { dragOffset = 0 }
        }
    }

    private func scroll(_ event: NSEvent) {
        if !event.momentumPhase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetScroll()
            return
        }
        if !event.hasPreciseScrollingDeltas {
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            wheelAmount += delta
            if abs(wheelAmount) >= 3 {
                step(wheelAmount < 0 ? 1 : -1)
                wheelAmount = 0
            }
            return
        }
        if event.phase.contains(.began) { resetScroll() }
        let change = swipe.move(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                                time: ProcessInfo.processInfo.systemUptime, phaseLess: event.phase.isEmpty)
        let count = interaction.level == .tabs ? visibleTabs.count : sessionWindows.count
        let selection = interaction.selection
        let offset = swipe.offset
        let atEdge = (selection == 0 && offset > 0) || (selection == count - 1 && offset < 0)
        // Devices without gesture phases have no lift event to clear a partial drag.
        let nextOffset: CGFloat = event.phase.isEmpty ? 0 : (atEdge ? offset * 0.25 : offset)
        if change != 0, (0..<count).contains(selection + change) {
            step(change)
        } else if dragOffset != nextOffset {
            dragOffset = nextOffset
        }
        scheduleRepeat()
    }

    private func scheduleRepeat() {
        let count = interaction.level == .tabs ? visibleTabs.count : sessionWindows.count
        guard interaction.level != .closed, swipe.direction != 0,
              (0..<count).contains(interaction.selection + swipe.direction) else {
            repeatTimer?.invalidate()
            repeatTimer = nil
            return
        }
        guard repeatTimer == nil else { return }
        let timer = Timer(timeInterval: swipe.delay(at: ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = nil
            let delta = self.swipe.tick(at: ProcessInfo.processInfo.systemUptime)
            let count = self.interaction.level == .tabs ? self.visibleTabs.count : self.sessionWindows.count
            if delta != 0, self.interaction.level != .closed, (0..<count).contains(self.interaction.selection + delta) {
                self.step(delta)
            }
            self.scheduleRepeat()
        }
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func clickWindow(_ index: Int) {
        guard sessionWindows.indices.contains(index) else { return }
        let window = sessionWindows[index]
        let browser = sessionChrome[window.id]
        let expandable = (browser?.tabs.count ?? 0) > 1
        let effect = interaction.choose(index, hasTabs: expandable)
        if expandable, let browser {
            tabLayoutSizes = browser.tabs.map { preview(for: window, tab: $0)?.size ?? window.frame.size }
            interaction.expand(tabIDs: browser.tabs.map(\.id), activeID: browser.activeTabID)
            resetScroll()
        } else { apply(effect) }
    }

    func clickTab(_ index: Int) { apply(interaction.choose(index, hasTabs: false)) }
    func back() { interaction.back(); resetScroll() }
    func cancel() { apply(interaction.cancel()) }

    private func dismiss() {
        panel?.orderOut(nil)
        tap.sessionOpen = false
        resetScroll()
    }

    private func apply(_ effect: Interaction.Effect) {
        switch effect {
        case .none: return
        case .cancelled:
            dismiss()
            // Nonactivating panel does not change the frontmost app, but restore key focus if needed.
            startingApp?.activate(options: [])
        case .window(let id):
            dismiss()
            guard let target = sessionWindows.first(where: { $0.id == id }) else { return }
            if let browserID = target.chromeWindowID {
                chromeQueue.async {
                    do {
                        try ChromeService.select(windowID: browserID, tabID: nil)
                        DispatchQueue.main.async { self.noteUse(id) }
                    } catch { DispatchQueue.main.async { self.report(error.localizedDescription) } }
                }
                return
            }
            do { try WindowService.activate(target); noteUse(id) }
            catch { report(error.localizedDescription) }
        case .tab(let windowID, let tabID):
            dismiss()
            guard let chromeID = sessionChrome[windowID]?.id else { report("Chrome 窗口信息已失效，请重新打开总览。"); return }
            chromeQueue.async { [weak self] in
                do {
                    try ChromeService.select(windowID: chromeID, tabID: tabID)
                    DispatchQueue.main.async { self?.noteUse(windowID); self?.scheduleTabSample() }
                } catch { DispatchQueue.main.async { self?.report(error.localizedDescription) } }
            }
        }
    }

    private func noteUse(_ id: String) {
        mru.removeAll { $0 == id }; mru.insert(id, at: 0)
        refresh()
    }

    private func report(_ message: String) { status = message; onOpenSettings?() }

    private func captureSelectedAndRecent(forceSelected: Bool = false) {
        guard screenCapture else { return }
        guard !capturing else { capturePending = true; return }
        let targets: [WindowItem]
        if interaction.level != .closed {
            let index = sessionWindows.firstIndex { $0.id == currentWindow?.id } ?? 0
            let indices = [index, index+1, index-1].filter { sessionWindows.indices.contains($0) }
            targets = indices.map { sessionWindows[$0] }.filter {
                (forceSelected && $0.id == currentWindow?.id) || images[$0.id]?.image(for: $0) == nil
            }
        } else { targets = Array(windows.prefix(6)).filter { images[$0.id]?.image(for: $0) == nil } }
        guard !targets.isEmpty else { return }
        capturing = true
        Task { @MainActor [weak self] in
            let result = await WindowService.images(for: targets)
            guard let self else { return }
            guard CGPreflightScreenCaptureAccess() else {
                self.images.removeAll(); self.screenCapture = false; self.capturing = false; return
            }
            let liveWindows = Dictionary(self.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.images.merge(result.filter { entry in
                guard let current = liveWindows[entry.key] else { return false }
                return entry.value.image(for: current) != nil
            }, uniquingKeysWith: { _, new in new })
            self.capturing = false
            if self.capturePending {
                self.capturePending = false
                self.captureSelectedAndRecent(forceSelected: self.interaction.level != .closed)
            }
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func requestScreenCapture() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
