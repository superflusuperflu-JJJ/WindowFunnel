import Foundation
import FunnelCore

final class InteractionTests {
    func testFirstTabSelectsPreviousWindow() {
        var s = Interaction()
        s.begin(windowIDs: ["current", "previous", "older"], currentID: "current")
        expectEqual(s.selectedID, "previous")
        expectEqual(s.releaseCommand(), .window("previous"))
        expectEqual(s.level, .closed)
    }
    func testCurrentWindowMayBeInMiddleOfHistory() {
        var s = Interaction()
        s.begin(windowIDs: ["previous", "current", "older"], currentID: "current")
        expectEqual(s.selectedID, "previous")
    }
    func testWindowCyclingWrapsBothDirections() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "b", "c"], currentID: "a")
        s.step(2)
        expectEqual(s.selectedID, "a")
        s.step(-1)
        expectEqual(s.selectedID, "c")
    }
    func testReleasingCommandAfterExpansionKeepsTabsOpen() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "chrome"], currentID: "a")
        s.expand(tabIDs: ["t1", "t2", "t3"], activeID: "t2")
        expectEqual(s.selectedID, "t2")
        expectEqual(s.releaseCommand(), .none)
        expectEqual(s.level, .tabs)
        s.step(1)
        expectEqual(s.choose(2, hasTabs: false), .tab(window: "chrome", tab: "t3"))
        expectEqual(s.level, .closed)
    }
    func testBackRemainsLatchedAndPreservesWindowSelection() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "chrome", "b"], currentID: "a")
        s.expand(tabIDs: ["t1", "t2"], activeID: "t1")
        s.step(1)
        s.back()
        expectEqual(s.selectedID, "chrome")
        expectTrue(s.latched)
        expectEqual(s.releaseCommand(), .none)
        expectEqual(s.choose(0, hasTabs: false), .window("a"))
    }
    func testClickSelectsWindowBeforeExpansion() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "b", "chrome"], currentID: "a")
        expectEqual(s.choose(2, hasTabs: true), .none)
        s.expand(tabIDs: ["x", "y"], activeID: "x")
        expectEqual(s.parentID, "chrome")
    }
    func testOrdinaryWindowClickCommitsImmediately() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "notes"], currentID: "a")
        expectEqual(s.choose(1, hasTabs: false), .window("notes"))
    }
    func testNoWindowsDoesNotOpenSwitcher() {
        var s = Interaction()
        s.begin(windowIDs: [], currentID: nil)
        s.step(1)
        expectEqual(s.level, .closed)
        expectNil(s.selectedID)
        expectEqual(s.releaseCommand(), .none)
    }
    func testOnlyWindowReturnsItself() {
        var s = Interaction()
        s.begin(windowIDs: ["one"], currentID: "one")
        expectEqual(s.releaseCommand(), .window("one"))
    }
    func testCancellationClearsSessionAndDoesNotCommitLater() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "b"], currentID: "a")
        expectEqual(s.cancel(), .cancelled)
        expectEqual(s.level, .closed)
        expectEqual(s.releaseCommand(), .none)
        expectNil(s.selectedID)
    }
    func testInvalidClickCannotCommitDifferentTarget() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "b"], currentID: "a")
        expectEqual(s.choose(99, hasTabs: false), .none)
        expectEqual(s.selectedID, "b")
    }
    func testEmptyTabsCannotLatchOrLoseSelectedWindow() {
        var s = Interaction()
        s.begin(windowIDs: ["a", "chrome"], currentID: "a")
        s.expand(tabIDs: [], activeID: nil)
        expectEqual(s.level, .windows)
        expectFalse(s.latched)
        expectEqual(s.releaseCommand(), .window("chrome"))
    }
}

var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, line: Int = #line) { if actual != expected { failures += 1; print("FAIL line \(line): \(actual) != \(expected)") } }
func expectTrue(_ actual: Bool, line: Int = #line) { expectEqual(actual, true, line: line) }
func expectFalse(_ actual: Bool, line: Int = #line) { expectEqual(actual, false, line: line) }
func expectNil<T>(_ actual: T?, line: Int = #line) { if actual != nil { failures += 1; print("FAIL line \(line): expected nil") } }
@main struct Checks { static func main() { let tests = InteractionTests()
var swipe = SwipePaging()
expectEqual(swipe.move(x: -30, y: 3, time: 0, phaseLess: false), 0)
expectEqual(swipe.offset, -30)
expectEqual(swipe.move(x: -20, y: 2, time: 0.1, phaseLess: false), 1)
expectEqual(swipe.move(x: -200, y: 2, time: 0.5, phaseLess: false), 0)
expectEqual(swipe.tick(at: 0.69), 0)
expectEqual(swipe.tick(at: 0.71), 1)
expectEqual(swipe.tick(at: 0.72), 0)
expectEqual(swipe.move(x: 55, y: 0, time: 0.8, phaseLess: false), -1)
expectEqual(swipe.tick(at: 1.39), 0)
expectEqual(swipe.tick(at: 1.41), -1)
swipe = SwipePaging()
expectEqual(swipe.tick(at: 2), 0)
expectEqual(swipe.move(x: 80, y: 0, time: 1, phaseLess: true), -1)
expectEqual(swipe.tick(at: 2), 0)
swipe = SwipePaging()
expectEqual(swipe.move(x: 2, y: 60, time: 0, phaseLess: false), 0)
expectEqual(swipe.move(x: 160, y: 0, time: 0.1, phaseLess: false), 0)
runIdentityChecks()
runChromeConnectionChecks()
runPreviewPolicyChecks()
tests.testFirstTabSelectsPreviousWindow()
tests.testCurrentWindowMayBeInMiddleOfHistory()
tests.testWindowCyclingWrapsBothDirections()
tests.testReleasingCommandAfterExpansionKeepsTabsOpen()
tests.testBackRemainsLatchedAndPreservesWindowSelection()
tests.testClickSelectsWindowBeforeExpansion()
tests.testOrdinaryWindowClickCommitsImmediately()
tests.testNoWindowsDoesNotOpenSwitcher()
tests.testOnlyWindowReturnsItself()
tests.testCancellationClearsSessionAndDoesNotCommitLater()
tests.testInvalidClickCannotCommitDifferentTarget()
tests.testEmptyTabsCannotLatchOrLoseSelectedWindow()
print("Ran 12 scenarios; \(failures) failed assertions"); if failures > 0 { exit(1) } } }
