// Start paging after a deliberate horizontal drag. A phase-aware trackpad
// keeps the direction armed until lift, cancellation, or a deliberate reversal.
public struct SwipePaging {
    public static let repeatInterval = 0.60
    public private(set) var direction = 0
    private var travel = 0.0
    private var vertical = 0.0
    private var reverseTravel = 0.0
    private var blocked = false
    private var lastEvent: Double?
    private var lastPage: Double?
    public var offset: Double { blocked || direction != 0 || abs(travel) <= abs(vertical) ? 0 : travel }
    public init() {}

    public mutating func move(x: Double, y: Double, time: Double, phaseLess: Bool) -> Int {
        if phaseLess, let lastEvent, time - lastEvent > 0.18 { self = Self() }
        lastEvent = time
        guard !blocked else { return 0 }
        if direction != 0 {
            reverseTravel = max(0, reverseTravel + x * Double(direction))
            guard reverseTravel >= 12 else { return 0 }
            travel = reverseTravel * Double(direction)
            reverseTravel = 0
            direction = 0
            vertical = y
        } else {
            travel += x
            vertical += y
        }
        if abs(vertical) >= 12 && abs(vertical) > abs(travel) * 1.25 {
            blocked = true
            return 0
        }
        let threshold: Double = phaseLess ? 70 : 50
        guard abs(travel) >= threshold, abs(travel) > abs(vertical) else { return 0 }
        direction = travel < 0 ? 1 : -1
        travel = 0
        // A deliberate swipe (including a reversal) starts immediately. Only
        // timer-driven advances wait for the repeat interval.
        let page = direction
        lastPage = time
        if phaseLess { blocked = true; direction = 0 }
        return page
    }

    public mutating func tick(at time: Double) -> Int {
        guard direction != 0 else { return 0 }
        if let lastPage, time < lastPage + Self.repeatInterval { return 0 }
        lastPage = time
        return direction
    }

    public func delay(at time: Double) -> Double {
        max(0, (lastPage ?? time) + Self.repeatInterval - time)
    }
}
