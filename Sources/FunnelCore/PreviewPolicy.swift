import Foundation

public enum WindowPolicy {
    public static func isMainWindow(role: String?, subrole: String?, uniquelyMatched: Bool, supportsRaise: Bool) -> Bool {
        return uniquelyMatched && supportsRaise && role == "AXWindow" && (subrole == "AXStandardWindow" || subrole == "AXDialog")
    }
}

public struct PreviewIdentity: Equatable {
    public let windowID: UInt32
    public let processID: Int32
    public let title: String
    public let x: Double, y: Double, width: Double, height: Double
    public init(windowID: UInt32, processID: Int32, title: String, x: Double, y: Double, width: Double, height: Double) {
        self.windowID = windowID; self.processID = processID; self.title = title
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum PreviewPolicy {
    public static let maximumAge: TimeInterval = 8
    public static func canUse(captured: PreviewIdentity, current: PreviewIdentity, age: TimeInterval) -> Bool {
        captured == current && age >= 0 && age <= maximumAge
    }
}
