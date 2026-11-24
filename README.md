# WindowFunnel · 窗口切换器

WindowFunnel 是一个原生 macOS 菜单栏应用。按住 ⌘Tab 可以用大幅预览浏览各个窗口，双指左右滑动即可切换；点选多标签页的 Chrome 窗口，还可以按原有顺序浏览标签页的最近快照。

## 从源码安装

需要 macOS 14 或更高版本，以及支持 Swift 5.9 和 macOS 14 SDK 的 Xcode 或 Command Line Tools。项目使用系统框架，无第三方包。本地构建使用临时签名，无需 Apple Developer 会员或 Chrome 扩展。

1. 首次使用开发工具时，在终端运行 `xcode-select --install`，等待安装完成。已安装工具的 Mac 可以跳过这一步。
2. 在终端下载源码，在项目目录内构建并打开应用。

```sh
git clone https://github.com/superflusuperflu-JJJ/WindowFunnel.git
cd WindowFunnel
bash scripts/build-app.sh
open dist/WindowFunnel.app
```

也可以在 GitHub 点 **Code → Download ZIP**，解压后在该文件夹打开终端，执行上面的最后两行命令。建议把源码放在打算长期保留的位置，之后始终打开同一份应用。重新构建后，macOS 有时会要求重新授权。

## 首次运行

1. 在控制窗口点“前往设置”，在系统设置 → 隐私与安全性 → 辅助功能中允许本应用。若列表中没有它，用 `+` 添加 `dist/WindowFunnel.app`。
2. 点“开启预览权限”，按系统提示允许屏幕录制。应用不捕获音频。若 macOS 要求退出并重新打开，请照提示操作；同一时刻只运行一份原型。
3. 点“连接 Chrome”，由你确认系统自动化提示。该项用于浏览普通窗口中的标签页；使用其他应用的窗口切换时可以跳过。
4. 点“开启 Command-Tab”，回到平常工作窗口开始体验。菜单栏随时可以暂停或退出；没有开启时保留系统 Command-Tab。

权限由 macOS 管理，本项目不会自动更改系统授权。没有屏幕权限也能通过应用图标和标题体验总览；窗口列表只收录辅助功能能唯一定位且支持置前的窗口；其他桌面暂未暴露的窗口可能缺席。

## 操作

| 操作 | 行为 |
| --- | --- |
| 首次按住 Command 并按 Tab | 打开总览，选中上一个使用的窗口 |
| 继续按 Tab / Shift-Tab / 左右键 / 双指横向滑动 | 前后浏览窗口 |
| 第一层松开 Command | 进入选中窗口，保留它原来的活动标签页 |
| 点击多标签 Chrome 窗口 | 展开标签页，并进入可松手状态 |
| 第二层松开 Command | 保持总览打开 |
| 第二层点标签页 | 进入该标签页 |
| 返回窗口 | 保持可松手状态，继续点选 |
| Esc / 点击背景 | 取消本次选择 |

“打开总览”按钮提供无需按住 Command 的鼠标体验入口。关闭设置窗口不会退出应用；菜单栏“退出窗口原型”才会退出。

## 快照与使用范围

- 普通标签页快照存放在 `~/Library/Application Support/WindowFunnel/TabPreviews/`，可能包含网页或在线文档的可见内容。
- Chrome 普通标签页按原有顺序展示最近浏览快照。每次采样会核对活动标签和网址，每个普通标签页在本机保留一张最近快照，在仍打开的窗口内关闭标签后，读取 Chrome 的关闭记录清理。支持以 Chrome 会话文件的持久标识恢复重启前的快照，未采到时显示标题和网址。
- 系统窗口编号与 Chrome 自动化编号分别管理，按标题和几何信息建立一对一映射；无法唯一对应时不猜测，也不展开错误窗口。
- 同名、同位置、同尺寸的窗口有时无法通过公开元数据精确区分；原型会报告无法定位，而不随意激活另一个窗口。
- 窗口预览是快照，可能滞后；没有截图时明确显示占位。窗口层截图只在内存中存在。
- 最近使用历史从启动后开始记录；通过应用激活和窗口焦点通知更新，并定期校对。不能恢复启动前完整使用历史。
- 跨桌面、全屏和最小化窗口的激活效果需要结合本机设置实际验证；不使用私有 Spaces API。
- Finder 本轮按窗口处理，尚未支持 Finder 标签页和文件搜索。
- 默认使用本地临时签名；可通过环境变量 `WINDOW_FUNNEL_SIGNING_IDENTITY` 指定已有的 Apple Development 签名身份，无发布、公证、自动更新或开机启动。

## 构建与检查

需要 Apple Silicon 或 Intel Mac、macOS 14+、Swift 5.9+ 和 Apple 命令行工具；无第三方依赖。

```sh
swift run FunnelCoreChecks
bash scripts/build-app.sh
codesign --verify --deep --strict dist/WindowFunnel.app
```

当前电脑的命令行工具不包含 XCTest，因此核心检查使用独立 Swift 可执行程序；断言失败时返回非零状态，不依赖网络安装测试框架。

`swift run WindowFunnel --diagnose` 可输出权限状态、窗口数量和能够精确对应的窗口数量，不输出窗口标题或网址。它只说明命令行进程的权限，不能代替打包应用的权限验证。

## 源码

- `Sources/FunnelCore`：按住 / 可松手状态机，带歧义检查的窗口身份匹配。
- `Sources/WindowFunnel`：菜单栏、权限控制、原生总览、事件拦截、窗口与 Chrome 接入。
- `Tests/FunnelCoreTests`：交互与身份匹配检查。
