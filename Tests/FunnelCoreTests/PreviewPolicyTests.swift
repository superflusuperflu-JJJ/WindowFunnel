import FunnelCore

func runPreviewPolicyChecks() {
    // A titled CG surface (including an opaque TencentMeeting helper) is insufficient.
    expectFalse(WindowPolicy.isMainWindow(role: nil, subrole: nil, uniquelyMatched: false, supportsRaise: false))
    expectFalse(WindowPolicy.isMainWindow(role: "AXWindow", subrole: "AXStandardWindow", uniquelyMatched: false, supportsRaise: true))
    expectFalse(WindowPolicy.isMainWindow(role: "AXWindow", subrole: "AXStandardWindow", uniquelyMatched: true, supportsRaise: false))
    expectFalse(WindowPolicy.isMainWindow(role: "AXWindow", subrole: "AXFloatingWindow", uniquelyMatched: true, supportsRaise: true))
    expectTrue(WindowPolicy.isMainWindow(role: "AXWindow", subrole: "AXStandardWindow", uniquelyMatched: true, supportsRaise: true))
    expectTrue(WindowPolicy.isMainWindow(role: "AXWindow", subrole: "AXDialog", uniquelyMatched: true, supportsRaise: true))

    let old = PreviewIdentity(windowID: 80, processID: 123, title: "Document A", x: 0, y: 20, width: 1000, height: 700)
    let changed = PreviewIdentity(windowID: 80, processID: 123, title: "Document B", x: 0, y: 20, width: 1000, height: 700)
    let reused = PreviewIdentity(windowID: 80, processID: 456, title: "Document A", x: 0, y: 20, width: 1000, height: 700)
    let resized = PreviewIdentity(windowID: 80, processID: 123, title: "Document A", x: 0, y: 20, width: 800, height: 700)
    expectTrue(PreviewPolicy.canUse(captured: old, current: old, age: 2))
    expectFalse(PreviewPolicy.canUse(captured: old, current: changed, age: 2))
    expectFalse(PreviewPolicy.canUse(captured: old, current: reused, age: 2))
    expectFalse(PreviewPolicy.canUse(captured: old, current: resized, age: 2))
    expectFalse(PreviewPolicy.canUse(captured: old, current: old, age: 9))
    expectFalse(PreviewPolicy.canUse(captured: old, current: old, age: -1))
    print("Ran 12 main-window and preview identity/age checks")
}
