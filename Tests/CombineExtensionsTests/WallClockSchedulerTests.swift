import Combine
import CombineExtensions
import XCTest

final class WallClockSchedulerTests: XCTestCase {
    func testSchedulerTimeTypeUsesDateArithmetic() {
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let time = WallClockScheduler.SchedulerTimeType(date)

        let advanced = time.advanced(by: .milliseconds(250))

        XCTAssertEqual(advanced.date, date.addingTimeInterval(0.25))
        XCTAssertEqual(time.distance(to: advanced).timeInterval, 0.25, accuracy: 0.000_001)
    }

    func testNowUsesCurrentWallClockDate() {
        let scheduler = makeScheduler()
        let before = Date()

        let now = scheduler.now.date

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, Date())
    }

    func testImmediateActionRunsOnDispatchQueue() {
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: #function)
        queue.setSpecific(key: key, value: #function)
        let scheduler = WallClockScheduler(queue: queue)
        let executed = expectation(description: "Executed")

        scheduler.schedule {
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), #function)
            executed.fulfill()
        }

        wait(for: [executed], timeout: 1)
    }

    func testFutureActionRunsAtWallClockDeadline() {
        let scheduler = makeScheduler()
        let executed = expectation(description: "Executed")
        let deadline = Date().addingTimeInterval(0.01)
        var executedAt: Date?

        scheduler.schedule(
            after: .init(deadline),
            tolerance: .zero,
            options: nil
        ) {
            executedAt = Date()
            executed.fulfill()
        }

        wait(for: [executed], timeout: 1)
        XCTAssertGreaterThanOrEqual(executedAt ?? .distantPast, deadline)
    }

    func testPastActionRunsAtNextOpportunity() {
        let scheduler = makeScheduler()
        let executed = expectation(description: "Executed")

        scheduler.schedule(
            after: .init(.distantPast),
            tolerance: .zero,
            options: nil
        ) {
            executed.fulfill()
        }

        wait(for: [executed], timeout: 1)
    }

    func testRepeatingActionCanBeCancelled() {
        let scheduler = makeScheduler()
        let executed = expectation(description: "Executed")
        executed.expectedFulfillmentCount = 3
        var cancellable: Cancellable?
        var executionCount = 0

        cancellable = scheduler.schedule(
            after: scheduler.now.advanced(by: .milliseconds(1)),
            interval: .milliseconds(1),
            tolerance: .zero,
            options: nil
        ) {
            executionCount += 1
            executed.fulfill()

            if executionCount == 3 {
                cancellable?.cancel()
            }
        }

        wait(for: [executed], timeout: 1)
        XCTAssertEqual(executionCount, 3)
    }

    func testAgainAtRepublishesOnWallClockSchedulerQueue() {
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: #function)
        queue.setSpecific(key: key, value: #function)
        let scheduler = WallClockScheduler(queue: queue)
        let subject = PassthroughSubject<Int, Never>()
        let republished = expectation(description: "Republished")
        var values = [Int]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    XCTAssertEqual(DispatchQueue.getSpecific(key: key), #function)
                    values.append(value)

                    if values.count == 1 {
                        let date = Date().addingTimeInterval(0.01)
                        let time = timer.time(at: date)
                        XCTAssertDatesEqual(time.date, date, accuracy: 0.001)
                        timer.republish(at: time)
                    } else {
                        republished.fulfill()
                    }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)

        wait(for: [republished], timeout: 1)
        XCTAssertEqual(values, [1, 1])
    }

    private func makeScheduler() -> WallClockScheduler {
        WallClockScheduler(queue: DispatchQueue(label: #function))
    }
}

private func XCTAssertDatesEqual(
    _ lhs: Date,
    _ rhs: Date,
    accuracy: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        lhs.timeIntervalSinceReferenceDate,
        rhs.timeIntervalSinceReferenceDate,
        accuracy: accuracy,
        file: file,
        line: line
    )
}
