public struct Interaction {
    public enum Level: Equatable { case closed, windows, tabs }
    public enum Effect: Equatable { case none, window(String), tab(window: String, tab: String), cancelled }
    public private(set) var level: Level = .closed
    public private(set) var latched = false
    public private(set) var selection = 0
    public private(set) var windowIDs: [String] = []
    public private(set) var tabIDs: [String] = []
    public private(set) var parentID: String?
    public init() {}
    public var selectedID: String? {
        let ids = level == .tabs ? tabIDs : windowIDs
        guard level != .closed, ids.indices.contains(selection) else { return nil }
        return ids[selection]
    }
    public mutating func begin(windowIDs: [String], currentID: String?) {
        self = Interaction()
        self.windowIDs = windowIDs
        guard !windowIDs.isEmpty else { return }
        level = .windows
        selection = windowIDs.first == currentID && windowIDs.count > 1 ? 1 : 0
    }
    public mutating func step(_ delta: Int) {
        guard level != .closed else { return }
        let count = level == .tabs ? tabIDs.count : windowIDs.count
        guard count > 0 else { return }
        selection = ((selection + delta) % count + count) % count
    }
    public mutating func expand(tabIDs: [String], activeID: String?) {
        guard level == .windows, let parent = selectedID, !tabIDs.isEmpty else { return }
        parentID = parent
        self.tabIDs = tabIDs
        selection = tabIDs.firstIndex(of: activeID ?? "") ?? 0
        latched = true
        level = .tabs
    }
    public mutating func releaseCommand() -> Effect {
        guard level == .windows, !latched, let id = selectedID else { return .none }
        self = Interaction()
        return .window(id)
    }
    public mutating func back() {
        guard level == .tabs else { return }
        selection = windowIDs.firstIndex(of: parentID ?? "") ?? 0
        level = .windows
        tabIDs = []
        latched = true
    }
    public mutating func cancel() -> Effect {
        guard level != .closed else { return .none }
        self = Interaction()
        return .cancelled
    }
    public mutating func choose(_ index: Int, hasTabs: Bool) -> Effect {
        let ids = level == .tabs ? tabIDs : windowIDs
        guard level != .closed, ids.indices.contains(index) else { return .none }
        selection = index
        if level == .tabs, let parentID {
            let id = ids[index]
            self = Interaction()
            return .tab(window: parentID, tab: id)
        }
        guard !hasTabs else { return .none }
        let id = ids[index]
        self = Interaction()
        return .window(id)
    }
}
