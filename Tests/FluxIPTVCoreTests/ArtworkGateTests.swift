import XCTest
@testable import FluxIPTVCore

final class ArtworkGateTests:XCTestCase {
    func testBudgetAndCancellation() async throws {
        let gate=ArtworkGate(limit:2)
        let a=await gate.acquire(), b=await gate.acquire()
        XCTAssertTrue(a && b)
        let third=Task {await gate.acquire()}
        // Wait for the task to register, with a finite deadline.
        for _ in 0..<1000 {
            if await gate.counts().waiting == 1 {break}
            try await Task.sleep(nanoseconds:1_000_000)
        }
        let state=await gate.counts()
        XCTAssertEqual(state.active,2); XCTAssertEqual(state.waiting,1)
        third.cancel()
        let cancelled=await third.value
        XCTAssertFalse(cancelled)
        let fourth=Task {await gate.acquire()}
        await gate.release()
        let allowed=await fourth.value
        XCTAssertTrue(allowed)
        let during=await gate.counts()
        XCTAssertEqual(during.active,2)
        await gate.release(); await gate.release()
        let final=await gate.counts()
        XCTAssertEqual(final.active,0); XCTAssertEqual(final.waiting,0)
    }
}
