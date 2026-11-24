import Foundation

public struct WindowIdentity {
    public let id: String
    public let title: String
    public let x: Double, y: Double, width: Double, height: Double
    public init(id: String, title: String, x: Double, y: Double, width: Double, height: Double) {
        self.id = id; self.title = title; self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public enum IdentityMatcher {
    public static func uniqueMapping(native: [WindowIdentity], foreign: [WindowIdentity], allowUniqueGeometryFallback: Bool = false) -> [String: String] {
        func normalized(_ title: String) -> String {
            let suffix = " - Google Chrome"
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasSuffix(suffix) ? String(trimmed.dropLast(suffix.count)) : trimmed
        }
        func sameGeometry(_ a: WindowIdentity, _ b: WindowIdentity) -> Bool {
            abs(a.x-b.x)<3 && abs(a.y-b.y)<3 && abs(a.width-b.width)<3 && abs(a.height-b.height)<3
        }
        func shortenedMatch(_ short: String, _ full: String) -> Bool {
            let parts = short.components(separatedBy: "…")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
            return full.hasPrefix(parts[0]) && full.hasSuffix(parts[1]) && full.count >= parts[0].count+parts[1].count
        }
        func matches(_ a: WindowIdentity, _ b: WindowIdentity) -> Bool {
            let titleA = normalized(a.title), titleB = normalized(b.title)
            return sameGeometry(a,b) && (titleA.isEmpty || titleB.isEmpty || titleA == titleB
                || shortenedMatch(titleA,titleB) || shortenedMatch(titleB,titleA))
        }
        var result: [String: String] = [:]
        for source in native {
            let candidates = foreign.filter { matches(source, $0) }
            guard candidates.count == 1, let target = candidates.first,
                  native.filter({ matches($0, target) }).count == 1 else { continue }
            result[source.id] = target.id
        }
        if allowUniqueGeometryFallback {
            for source in native where result[source.id] == nil {
                let candidates = foreign.filter { sameGeometry(source,$0) }
                guard candidates.count == 1, let target = candidates.first,
                      !result.values.contains(target.id),
                      native.filter({ sameGeometry($0,target) }).count == 1 else { continue }
                result[source.id] = target.id
            }
        }
        return result
    }
}
