import XCTest
@testable import FluxIPTVCore

final class CaseInspectorNavigationTests: XCTestCase {
    func testVerticalSelectionNeverStartsPlayback() {
        var navigation=CaseInspectorNavigation()
        XCTAssertEqual(navigation.target,.object)
        XCTAssertEqual(navigation.handle(action:.up,at:0),.focus(.preview))
        XCTAssertEqual(navigation.handle(action:.up,at:1),.focus(.play))
        XCTAssertEqual(navigation.handle(action:.up,at:2),.none)
        XCTAssertEqual(navigation.handle(action:.down,at:3),.focus(.preview))
        XCTAssertEqual(navigation.handle(action:.down,at:4),.focus(.dismiss))
        XCTAssertEqual(navigation.handle(action:.up,at:5),.focus(.preview))
    }

    func testValidateAndDedicatedPlayAreDistinct() {
        var navigation=CaseInspectorNavigation()
        XCTAssertEqual(navigation.handle(action:.select,at:0),.focus(.preview))
        XCTAssertEqual(navigation.handle(action:.select,at:1),.activate(.preview))
        for target in CaseInspectorNavigation.Target.allCases {
            navigation.focus(target)
            XCTAssertEqual(navigation.handle(action:.playPause,at:2),.activate(.play))
            XCTAssertEqual(navigation.target,target)
        }
        navigation.focus(.play)
        XCTAssertEqual(navigation.handle(action:.select,at:3),.activate(.play))
    }

    func testBottomRowChangesFocusWithoutRotatingOrSkippingTitles() {
        var navigation=CaseInspectorNavigation(target:.dismiss)
        XCTAssertEqual(navigation.handle(action:.left,at:0),.none)
        XCTAssertEqual(navigation.handle(action:.right,at:0.1),.focus(.more))
        XCTAssertEqual(navigation.handle(action:.right,at:0.2),.focus(.favorite))
        XCTAssertEqual(navigation.handle(action:.right,at:0.3),.none)
        XCTAssertEqual(navigation.handle(action:.select,at:0.4),.activate(.favorite))
        XCTAssertEqual(navigation.handle(action:.left,at:0.5),.focus(.more))
        XCTAssertEqual(navigation.handle(action:.left,at:0.6),.focus(.dismiss))
    }

    func testSingleTurnsAndBoundedDoublePresses() {
        for target in [CaseInspectorNavigation.Target.preview,.play] {
            var navigation=CaseInspectorNavigation(target:target)
            XCTAssertEqual(navigation.handle(action:.right,at:0),.rotate(25))
            XCTAssertEqual(navigation.target,.object)
        }
        for interval in [0.08,0.16,0.30] {
            var navigation=CaseInspectorNavigation()
            XCTAssertEqual(navigation.handle(action:.left,at:10),.rotate(-25))
            XCTAssertEqual(navigation.handle(action:.left,at:10+interval),.neighbor(-1))
            XCTAssertEqual(navigation.handle(action:.left,at:10+interval+0.1),.rotate(-25),"A triple press is not two title changes")
        }
        for interval in [0.01,0.079,0.301,2] {
            var navigation=CaseInspectorNavigation()
            XCTAssertEqual(navigation.handle(action:.right,at:10),.rotate(25))
            XCTAssertEqual(navigation.handle(action:.right,at:10+interval),.rotate(25))
        }
        var navigation=CaseInspectorNavigation()
        XCTAssertEqual(navigation.handle(action:.left,at:1),.rotate(-25))
        XCTAssertEqual(navigation.handle(action:.right,at:1.15),.rotate(25))
    }

    func testRepeatsAndOtherCommandsInvalidateDoublePress() {
        var navigation=CaseInspectorNavigation()
        XCTAssertEqual(navigation.handle(action:.right,at:1),.rotate(25))
        XCTAssertEqual(navigation.handle(action:.right,at:1.1,repeating:true),.rotate(25))
        XCTAssertEqual(navigation.handle(action:.right,at:1.2),.rotate(25))
        XCTAssertEqual(navigation.handle(action:.up,at:1.25),.focus(.preview))
        XCTAssertEqual(navigation.handle(action:.right,at:1.3),.rotate(25))
        navigation.focus(.object)
        XCTAssertEqual(navigation.handle(action:.right,at:1.4),.rotate(25))
        _ = navigation.handle(action:.volumeUp,at:1.45)
        XCTAssertEqual(navigation.handle(action:.right,at:1.5),.rotate(25))
        XCTAssertEqual(navigation.handle(action:.right,at:.nan),.rotate(25))
        XCTAssertEqual(navigation.handle(action:.right,at:1.6),.rotate(25))
    }

    func testReturnAndOptionsHaveOneClearDestination() {
        var navigation=CaseInspectorNavigation()
        XCTAssertEqual(navigation.handle(action:.options,at:0),.activate(.more))
        XCTAssertEqual(navigation.target,.more)
        XCTAssertEqual(navigation.handle(action:.back,at:1),.close)
        XCTAssertEqual(navigation.handle(action:.home,at:2),.close)
    }
}
