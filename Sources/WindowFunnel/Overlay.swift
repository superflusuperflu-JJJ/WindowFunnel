import AppKit
import SwiftUI
import FunnelCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private let material = NSVisualEffectView()
    private let foreground = NSView()
    private let entranceKey = "overviewEntrance"

    func install(_ view: NSView) {
        let container = NSView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        foreground.wantsLayer = true
        for child in [material, foreground] {
            child.frame = container.bounds
            child.autoresizingMask = [.width, .height]
            container.addSubview(child)
        }
        view.frame = foreground.bounds
        view.autoresizingMask = [.width, .height]
        foreground.addSubview(view)
        contentView = container
    }

    func presentOverview() {
        contentView?.layoutSubtreeIfNeeded()
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = 0.26
        // Animate the real desktop material along with the overlay, on every presentation.
        alphaValue = reduced ? 1 : 0
        if let layer = foreground.layer {
            layer.removeAnimation(forKey: entranceKey)
            if !reduced {
                // Keep the screen centre stationary regardless of AppKit's layer anchor.
                let bounds = layer.bounds
                let x = bounds.width * (0.5 - layer.anchorPoint.x)
                let y = bounds.height * (0.5 - layer.anchorPoint.y)
                let scale: CGFloat = 1.15
                let zoom = CABasicAnimation(keyPath: "transform")
                var start = CATransform3DMakeTranslation(x * (1 - scale), y * (1 - scale), 0)
                start = CATransform3DScale(start, scale, scale, 1)
                zoom.fromValue = NSValue(caTransform3D: start)
                zoom.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                zoom.duration = duration
                zoom.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.25, 1)
                layer.add(zoom, forKey: entranceKey)
            }
        }
        makeKeyAndOrderFront(nil)
        guard !reduced else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        hasShadow = false
        isMovable = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        setAccessibilityLabel("窗口切换总览")
    }
}

private struct CardRowTranslation: GeometryEffect {
    var x: CGFloat
    var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

struct OverlayView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var isTabs: Bool { coordinator.interaction.level == .tabs }
    var count: Int { isTabs ? coordinator.visibleTabs.count : coordinator.sessionWindows.count }

    var body: some View {
        GeometryReader { geometry in
            let layout = CardLayout(sources: isTabs ? coordinator.tabLayoutSizes : coordinator.windowLayoutSizes, viewport: geometry.size, limitToSourceSize: true)
            let selected = coordinator.interaction.selection
            let center = layout.centers.indices.contains(selected) ? layout.centers[selected] : 0
            ZStack {
                Color.black.opacity(0.30).ignoresSafeArea().onTapGesture { coordinator.cancel() }
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(isTabs ? "标签页" : "窗口").font(.system(size: 25, weight: .semibold))
                            Text(isTabs ? (coordinator.currentWindow?.title ?? "Chrome") : "先看内容，再选目标")
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }
                        Spacer()
                        Text(coordinator.interaction.latched ? "可以松开 ⌘ · 点击进入" : "按住 ⌘ 浏览 · 松开进入")
                            .font(.system(size: 13, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 9)
                            .background(.white.opacity(0.12), in: Capsule())
                        Button { coordinator.cancel() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                            .buttonStyle(.plain).accessibilityLabel("取消切换")
                    }.padding(.horizontal, 44).padding(.top, 30)
                    Spacer(minLength: 16)
                    HStack(spacing: CardLayout.spacing) {
                        if isTabs {
                            ForEach(Array(coordinator.visibleTabs.enumerated()), id: \.element.id) { index, tab in
                                itemCard(window: coordinator.currentWindow, tab: tab, index: index, size: layout.previews[index])
                            }
                        } else {
                            ForEach(Array(coordinator.sessionWindows.enumerated()), id: \.element.id) { index, window in
                                itemCard(window: window, tab: nil, index: index, size: layout.previews[index])
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: geometry.size.width, alignment: .leading)
                    // Only the row translates. Preview arrivals and card contents settle in place.
                    .transaction { $0.animation = nil }
                    .modifier(CardRowTranslation(x: geometry.size.width / 2 - center + (reduceMotion ? 0 : coordinator.dragOffset)))
                    .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.13, extraBounce: 0, blendDuration: 0), value: selected)
                    // Discard any in-flight row movement when reopening or changing level.
                    .id(coordinator.presentationID.uuidString + (isTabs ? "-tabs" : "-windows"))
                    Spacer(minLength: 16)
                    HStack {
                        if isTabs {
                            Button { coordinator.back() } label: { Label("返回窗口", systemImage: "chevron.left") }.buttonStyle(.plain)
                        } else { Text("左右滑动 · 方向键 · Tab").foregroundStyle(.white.opacity(0.6)) }
                        Spacer()
                        Button { coordinator.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("上一个")
                        Text("\(count == 0 ? 0 : coordinator.interaction.selection+1) / \(count)").monospacedDigit().frame(minWidth: 62)
                        Button { coordinator.step(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("下一个")
                        Spacer()
                        Text("点击背景取消 · Esc").foregroundStyle(.white.opacity(0.6))
                    }.font(.system(size: 13)).padding(.horizontal, 44).padding(.bottom, 30)
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func itemCard(window: WindowItem?, tab: ChromeTab?, index: Int, size: CGSize) -> some View {
        let selected = index == coordinator.interaction.selection
        let chromeWindow = window.flatMap { coordinator.sessionChrome[$0.id] }
        let expandable = (chromeWindow?.tabs.count ?? 0) > 1
        return Button {
            if isTabs { coordinator.clickTab(index) } else { coordinator.clickWindow(index) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    if let icon = window?.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    Text(tab?.title ?? window?.title ?? "窗口")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 0)
                    if expandable && tab == nil {
                        Text("\(chromeWindow?.tabs.count ?? 0) 个标签页 ›").font(.caption).lineLimit(1)
                    }
                }.padding(.horizontal, 10).frame(height: 40)
                Group {
                    if let window, let image = coordinator.preview(for: window, tab: tab) {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 17) {
                            if let icon = window?.icon { Image(nsImage: icon).resizable().frame(width: 64, height: 64) }
                            Text(tab == nil ? "暂无窗口预览" : "暂无此标签页的内容预览").font(.system(size: 16, weight: .medium))
                            Text(tab == nil ? "可通过应用与标题辨认；屏幕录制权限开启后显示快照。" : "在 Chrome 中浏览此页后，这里会显示最近的页面快照。")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center).padding(.horizontal, 30)
                            if let tab { Text(tab.url).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(3).padding(.horizontal, 32) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(width: size.width, height: size.height)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding([.horizontal, .bottom], CardLayout.inset)
            .frame(width: size.width + 2 * CardLayout.inset)
            .background(Color(red: 0.12, green: 0.15, blue: 0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? .white.opacity(0.75) : .white.opacity(0.13), lineWidth: selected ? 2 : 1))
            .opacity(selected ? 1 : 0.65)
        }.buttonStyle(.plain)
        .accessibilityLabel("\(tab?.title ?? window?.title ?? "窗口")，\(tab == nil && expandable ? "展开标签页" : "进入")")
    }
}
