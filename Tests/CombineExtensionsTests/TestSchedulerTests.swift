import Combine
import CombineExtensions
import XCTest

// Taken from https://github.com/pointfreeco/combine-schedulers/blob/main/Tests/CombineSchedulersTests/TestSchedulerTests.swift
final class TestSchedulerTests: XCTestCase {
    var cancellables: Set<AnyCancellable> = []

    func testAdvance() {
        let scheduler = DispatchQueue.test

        var value: Int?
        Just(1)
            .delay(for: 1, scheduler: scheduler)
            .sink { value = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(value, nil)

        scheduler.advance(by: .milliseconds(250))
        XCTAssertEqual(value, nil)

        scheduler.advance(by: .milliseconds(250))
        XCTAssertEqual(value, nil)

        scheduler.advance(by: .milliseconds(250))
        XCTAssertEqual(value, nil)

        scheduler.advance(by: .milliseconds(250))
        XCTAssertEqual(value, 1)
    }

    func testRunScheduler() {
        let scheduler = DispatchQueue.test

        var value: Int?
        Just(1)
            .delay(for: 1_000_000_000, scheduler: scheduler)
            .sink { value = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(value, nil)

        scheduler.advance(by: 1_000_000)
        XCTAssertEqual(value, nil)

        scheduler.run()
        XCTAssertEqual(value, 1)
    }

    func testRunWithNoScheduledActionsDoesNotChangeNow() {
        let scheduler = DispatchQueue.test
        let now = scheduler.now

        scheduler.run()

        XCTAssertEqual(now, scheduler.now)
    }

    func testAdvanceWithNoScheduledActionsMovesNowToFinalDate() {
        let scheduler = DispatchQueue.test
        let now = scheduler.now

        scheduler.advance(by: .seconds(3))

        XCTAssertEqual(now.advanced(by: .seconds(3)), scheduler.now)
    }

    func testOneOffActionsAtSameDateRunInSchedulingOrder() {
        let scheduler = DispatchQueue.test
        var values = [Int]()

        scheduler.schedule(after: scheduler.now.advanced(by: .seconds(1))) {
            values.append(1)
        }

        scheduler.schedule(after: scheduler.now.advanced(by: .seconds(1))) {
            values.append(2)
        }

        scheduler.schedule(after: scheduler.now.advanced(by: .seconds(1))) {
            values.append(3)
        }

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual([1, 2, 3], values)
    }

    func testActionsScheduledForNowDuringAdvanceRunDuringSameAdvance() {
        let scheduler = DispatchQueue.test
        var values = [Int]()

        scheduler.schedule {
            values.append(1)
            scheduler.schedule { values.append(3) }
        }

        scheduler.schedule { values.append(2) }

        scheduler.advance()

        XCTAssertEqual([1, 2, 3], values)
    }

    func testCancellingIntervalRemovesFutureScheduledActions() {
        let scheduler = DispatchQueue.test
        var values = [Int]()

        let cancellable = scheduler.schedule(
            after: scheduler.now,
            interval: .seconds(1)
        ) {
            values.append(1)
        }

        scheduler.advance()
        cancellable.cancel()
        scheduler.advance(by: .seconds(5))

        XCTAssertEqual([1], values)
    }

    func testDelay0Advance() {
        let scheduler = DispatchQueue.test

        var value: Int?
        Just(1)
            .delay(for: 0, scheduler: scheduler)
            .sink { value = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(value, nil)

        scheduler.advance()
        XCTAssertEqual(value, 1)
    }

    func testSubscribeOnAdvance() {
        let scheduler = DispatchQueue.test

        var value: Int?
        Just(1)
            .subscribe(on: scheduler)
            .sink { value = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(value, nil)

        scheduler.advance()
        XCTAssertEqual(value, 1)
    }

    func testReceiveOnAdvance() {
        let scheduler = DispatchQueue.test

        var value: Int?
        Just(1)
            .receive(on: scheduler)
            .sink { value = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(value, nil)

        scheduler.advance()
        XCTAssertEqual(value, 1)
    }

    func testDispatchQueueDefaults() {
        let scheduler = DispatchQueue.test
        scheduler.advance(by: .nanoseconds(0))

        XCTAssertEqual(
            scheduler.now,
            .init(DispatchTime(uptimeNanoseconds: 1)),
            """
            Default of dispatchQueue.now should not be 0 because that has special meaning in DispatchTime's \
            initializer and causes it to default to DispatchTime.now().
            """
        )
    }

    func testTwoIntervalOrdering() {
        let testScheduler = DispatchQueue.test

        var values: [Int] = []

        testScheduler.schedule(after: testScheduler.now, interval: 2) { values.append(1) }
            .store(in: &cancellables)

        testScheduler.schedule(after: testScheduler.now, interval: 1) { values.append(42) }
            .store(in: &cancellables)

        XCTAssertEqual(values, [])
        testScheduler.advance()
        XCTAssertEqual(values, [1, 42])
        testScheduler.advance(by: 2)
        XCTAssertEqual(values, [1, 42, 42, 1, 42])
    }
}
