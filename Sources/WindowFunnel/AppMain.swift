import AppKit
import SwiftUI

@main enum AppMain {
    static func main() {
        if CommandLine.arguments.dropFirst().first == BackgroundPreview.origin { BackgroundPreview.relay(); return }
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--diagnose") {
            let windows = WindowService.scan()
            print("accessibility=\(AXIsProcessTrusted()) screenCapture=\(CGPreflightScreenCaptureAccess()) windows=\(windows.count) exactAXWindows=\(windows.filter { $0.element != nil }.count)")
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: Coordinator!
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator = Coordinator()
        coordinator.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "窗口切换原型")
        let menu = NSMenu()
        add("窗口 · 技术原型", to: menu, action: #selector(openSettings))
        menu.addItem(.separator())
        add("打开总览（鼠标体验）", to: menu, action: #selector(preview))
        add("开启 Command-Tab", to: menu, action: #selector(start))
        add("暂停，恢复系统切换", to: menu, action: #selector(stop))
        menu.addItem(.separator())
        add("权限与状态…", to: menu, action: #selector(openSettings))
        add("退出窗口原型", to: menu, action: #selector(quit))
        statusItem.menu = menu
        showSettings()
    }


    private func add(_ title: String, to menu: NSMenu, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
    @objc private func openSettings() { showSettings() }
    @objc private func preview() { coordinator.openPinnedPreview() }
    @objc private func start() { coordinator.start() }
    @objc private func stop() { coordinator.stop() }
    @objc private func quit() { coordinator.stop(); NSApp.terminate(nil) }

    private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "窗口 · 技术原型"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ControlView(coordinator: coordinator, preview: { [weak self] in self?.preview() }))
            window.center()
            settings = window
        }
        coordinator.refresh()
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        coordinator?.finishPendingWrites()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}

struct ControlView: View {
    @ObservedObject var coordinator: Coordinator
    var preview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 30)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("窗口").font(.system(size: 29, weight: .semibold))
                    Text("真实 Mac 技术原型 · 不联网 · 普通标签页快照仅保存在本机").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text("按住 ⌘ 找窗口，点击展开后松手找标签页。")
                .font(.system(size: 16, weight: .medium))
            VStack(spacing: 0) {
                permissionRow("辅助功能", detail: "用于接管 ⌘Tab、定位并切换真实窗口。", ready: coordinator.accessibility, button: "前往设置") { coordinator.openAccessibilitySettings() }
                Divider()
                permissionRow("屏幕与系统音频录制", detail: "仅捕获窗口画面，不采集音频；未授权时显示标题。", ready: coordinator.screenCapture, button: "开启预览权限") { coordinator.requestScreenCapture() }
                Divider()
                permissionRow("Chrome 自动化", detail: coordinator.chromeStatus, ready: coordinator.chromeConnection.isConnected, button: coordinator.chromeConnecting ? "连接中…" : coordinator.chromeConnection.isConnected ? "重新连接" : "连接 Chrome") { coordinator.connectChrome() }
            }.padding(.horizontal, 16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Circle().fill(coordinator.shortcutEnabled ? .green : .secondary).frame(width: 7, height: 7)
                Text(coordinator.status).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.frame(minHeight: 35, alignment: .leading)
            HStack(spacing: 12) {
                Button(coordinator.shortcutEnabled ? "暂停 Command-Tab" : "开启 Command-Tab") {
                    if coordinator.shortcutEnabled { coordinator.stop() } else { coordinator.start() }
                }.buttonStyle(.borderedProminent).tint(.green)
                Button("打开总览", action: preview).disabled(coordinator.windows.isEmpty)
                Button { coordinator.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新窗口和权限状态")
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("怎么体验").font(.system(size: 12, weight: .semibold))
                Text("① ⌘Tab 选中上个窗口；继续 Tab / 左右键 / 双指滑动切换。\n② 松开 ⌘ 直接进入；点击 Chrome 多标签窗口则展开标签页。\n③ 展开后可松开 ⌘，点击标签页进入；Esc 或点击背景取消。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                Text("本轮限制：Chrome 标签页显示最近浏览快照，尚未捕获时显示网址；窗口快照可能滞后。其他桌面切换仍需实测。访达暂按窗口处理。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }.padding(28).frame(width: 650, height: 650)
    }

    private func permissionRow(_ title: String, detail: String, ready: Bool, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ready ? .green : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action).font(.system(size: 11)).disabled(button == "连接中…")
        }.padding(.vertical, 15)
    }
}
