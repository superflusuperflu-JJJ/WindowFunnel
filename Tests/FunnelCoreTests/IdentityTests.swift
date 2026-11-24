import FunnelCore

func runIdentityChecks() {
    // Break caught: unrelated native/browser IDs must map by metadata, not numeric coincidence.
    let native = WindowIdentity(id: "900", title: "Research - Google Chrome", x: 0, y: 30, width: 1000, height: 700)
    let browser = WindowIdentity(id: "12", title: "Research", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [native], foreign: [browser]), ["900": "12"])
    let other = WindowIdentity(id: "901", title: "Research - Google Chrome", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [native, other], foreign: [browser]), [:])
    let duplicate = WindowIdentity(id: "13", title: "Research", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [native], foreign: [browser, duplicate]), [:])
    let wrong = WindowIdentity(id: "900", title: "Unrelated", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [native], foreign: [wrong]), [:])
    let moved = WindowIdentity(id: "12", title: "Research", x: 1200, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [native], foreign: [moved]), [:])
    let unnamed = WindowIdentity(id: "3", title: "", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [unnamed], foreign: [browser]), ["3": "12"])
    let shortened = WindowIdentity(id: "99", title: "Res…rch", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [shortened], foreign: [browser]), ["99": "12"])
    let note = WindowIdentity(id: "100", title: "My note", x: 0, y: 30, width: 1000, height: 700)
    let axNote = WindowIdentity(id: "0", title: "My note – 5 notes", x: 0, y: 30, width: 1000, height: 700)
    expectEqual(IdentityMatcher.uniqueMapping(native: [note], foreign: [axNote], allowUniqueGeometryFallback: true), ["100": "0"])
    expectEqual(IdentityMatcher.uniqueMapping(native: [native, other], foreign: [axNote], allowUniqueGeometryFallback: true), [:])
    print("Ran truncated-title and unique-geometry mapping checks")
    print("Ran 6 window identity scenarios")
}
