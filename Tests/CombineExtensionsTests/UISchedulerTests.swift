import Combine
import CombineExtensions
import XCTest

// Taken from https://github.com/pointfreeco/combine-schedulers/blob/main/Tests/CombineSchedulersTests/UISchedulerTests.swift
final class UISchedulerTests: XCTestCase {
    func testPublishersOnTheMainThreadPublishImmediately() throws {
        var didWork = false
        UIScheduler.shared.schedule { didWork = true }
        XCTAssertTrue(didWork)
    }

    func testRunsOnMain() {
        let queue = DispatchQueue(label: "queue")
        let exp = expectation(description: "wait")

        var worked = false
        queue.async {
            XCTAssert(!Thread.isMainThread)
            UIScheduler.shared.schedule {
                XCTAssert(Thread.isMainThread)
                worked = true
                exp.fulfill()
            }
            XCTAssertFalse(worked)
        }

        wait(for: [exp], timeout: 1)

        XCTAssertTrue(worked)
    }
}
