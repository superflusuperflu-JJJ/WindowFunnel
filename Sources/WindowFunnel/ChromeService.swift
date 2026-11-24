import AppKit

enum ChromeService {
    // Serialized Apple Events avoid concurrent requests and have a bounded execution timeout.
    static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw NativeError.message("Chrome 自动化脚本无法创建。") }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw NativeError.message("尚未允许控制 Chrome。请在系统设置 → 隐私与安全性 → 自动化中允许“窗口”控制 Google Chrome。") }
            throw NativeError.message("Chrome 暂时无法连接（\(code)）。请确认 Chrome 正在运行，再点“连接 Chrome”。")
        }
        return result
    }

    static func snapshot(activeOnly: Bool = false) -> ChromeSnapshot {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return ChromeSnapshot() }
        let source = """
        with timeout of 3 seconds
          tell application "Google Chrome"
            set output to {}
            repeat with w in windows
              if mode of w is "normal" then
                set tabRows to {}
                repeat with t in \(activeOnly ? "{active tab of w}" : "tabs of w")
                  set end of tabRows to {id of t as text, title of t as text, URL of t as text}
                end repeat
                set end of output to {id of w as text, title of w as text, id of active tab of w as text, tabRows, bounds of w}
              end if
            end repeat
            return output
          end tell
        end timeout
        """
        do {
            let output = try execute(source)
            guard output.descriptorType == typeAEList else { throw NativeError.message("Chrome 窗口清单不完整。") }
            var windows: [ChromeWindow] = []
            for i in 0..<output.numberOfItems {
                guard let row = output.atIndex(i+1), let id = row.atIndex(1)?.stringValue else { throw NativeError.message("Chrome 标签页清单不完整。") }
                var tabs: [ChromeTab] = []
                guard let list = row.atIndex(4), list.descriptorType == typeAEList else { throw NativeError.message("Chrome 标签页清单不完整。") }
                do {
                    for j in 0..<list.numberOfItems {
                        guard let tab = list.atIndex(j+1), let tabID = tab.atIndex(1)?.stringValue else { throw NativeError.message("Chrome 标签页清单不完整。") }
                        tabs.append(ChromeTab(id: tabID, title: tab.atIndex(2)?.stringValue ?? "无标题", url: tab.atIndex(3)?.stringValue ?? ""))
                    }
                }
                guard let bounds = row.atIndex(5), bounds.numberOfItems == 4 else { throw NativeError.message("Chrome 标签页清单不完整。") }
                let left = CGFloat(bounds.atIndex(1)?.int32Value ?? 0), top = CGFloat(bounds.atIndex(2)?.int32Value ?? 0)
                let right = CGFloat(bounds.atIndex(3)?.int32Value ?? 0), bottom = CGFloat(bounds.atIndex(4)?.int32Value ?? 0)
                windows.append(ChromeWindow(id: id, title: row.atIndex(2)?.stringValue ?? "Chrome", activeTabID: row.atIndex(3)?.stringValue, tabs: tabs,
                    frame: CGRect(x: left, y: top, width: right-left, height: bottom-top)))
            }
            return ChromeSnapshot(pid: app.processIdentifier, windows: windows)
        } catch { return ChromeSnapshot(error: error.localizedDescription) }
    }

    static func select(windowID: String, tabID: String?) throws {
        // IDs are validated numeric identifiers, never interpolated document titles or URLs.
        let digits = CharacterSet(charactersIn: "0123456789")
        guard !windowID.isEmpty,
              windowID.unicodeScalars.allSatisfy(digits.contains), tabID.map({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(digits.contains) }) ?? true else {
            throw NativeError.message("标签页标识无效，请刷新后重试。")
        }
        let result = try execute("""
        with timeout of 3 seconds
          tell application "Google Chrome"
            repeat with w in windows
              if (id of w as text) is "\(windowID)" then
                if mode of w is not "normal" then return false
                if \(tabID == nil ? "true" : "false") then
                    if minimized of w then set minimized of w to false
                    set index of w to 1
                    activate
                    return true
                end if
                repeat with i from 1 to count of tabs of w
                  if (id of tab i of w as text) is "\(tabID ?? "")" then
                    set active tab index of w to i
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end if
            end repeat
            return false
          end tell
        end timeout
        """)
        guard result.booleanValue else { throw NativeError.message("这个标签页或窗口已关闭。请重新打开总览。") }
    }
}
