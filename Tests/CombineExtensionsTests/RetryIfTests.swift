import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

final class RetryIfTests: XCTestCase {
    func testRetryIfAfterFixedInterval() throws {
        let scheduler = DispatchQueue.test

        let ex = [1]
            .publisher
            .failOnOutputIndex([0], error: .one)
            .retryIf(
                { $0 == .one },
                after: .seconds(1),
                scheduler: scheduler
            )
            .expectOutput(1)

        scheduler.advance(by: .seconds(1))
        wait(for: [ex], timeout: 1)
    }

    func testDoesNotRetryIfIntervalDidNotOccur() throws {
        let scheduler = DispatchQueue.test

        var output: [Int] = []
        let sub = [1]
            .publisher
            .failOnOutputIndex([0], error: .one)
            .retryIf(
                { $0 == .one },
                after: .seconds(1),
                scheduler: scheduler
            )
            .sink(
                receiveValue: { output.append($0) },
                receiveCompletion: { XCTAssertEqual(.finished, $0) }
            )
        defer { sub.cancel() }

        scheduler.advance(by: .milliseconds(500))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(500))
        XCTAssertEqual([1], output)
    }

    func testFailsIfPredicateDoesNotMatch() throws {
        let ex = Fail<Int, Err>(error: .two)
            .retryIf(
                { $0 == .one },
                after: .seconds(1),
                scheduler: RunLoop.main
            )
            .expectFailure(.two)

        wait(for: [ex], timeout: 1)
    }

    func testRetriesMultipleTimes() throws {
        let scheduler = DispatchQueue.test

        var output: [Int] = []
        let sub = [1, 2]
            .publisher
            .failOnOutputIndex([0, 1, 3], error: .one)
            .retryIf(
                { $0 == .one },
                after: .seconds(1),
                scheduler: scheduler
            )
            .sink(
                receiveValue: { output.append($0) },
                receiveCompletion: { XCTAssertEqual(.finished, $0) }
            )
        defer { sub.cancel() }

        scheduler.advance(by: .seconds(1))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(500))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(500))
        XCTAssertEqual([1], output)

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual([1, 1, 2], output)
    }

    func testRetriesAfterBackoff() throws {
        let scheduler = DispatchQueue.test

        var output: [Int] = []
        let sub = [1, 2]
            .publisher
            .failOnOutputIndex([0, 1, 2], error: .one)
            .retryIf(
                { $0 == .one },
                after: { .seconds($0) },
                scheduler: scheduler
            )
            .sink(
                receiveValue: { output.append($0) },
                receiveCompletion: { XCTAssertEqual(.finished, $0) }
            )
        defer { sub.cancel() }

        scheduler.advance(by: .seconds(1))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .seconds(2))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(2999))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual([1, 2], output)
    }

    func testBackoffResetsAfterSuccess() throws {
        let scheduler = DispatchQueue.test

        var output: [Int] = []
        let sub = [1, 2]
            .publisher
            .failOnOutputIndex([0, 1, 2, 4], error: .one)
            .retryIf(
                { $0 == .one },
                after: { .seconds($0) },
                scheduler: scheduler
            )
            .sink(
                receiveValue: { output.append($0) },
                receiveCompletion: { XCTAssertEqual(.finished, $0) }
            )
        defer { sub.cancel() }

        scheduler.advance(by: .milliseconds(5999))
        XCTAssertTrue(output.isEmpty)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual([1], output)

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual([1, 1, 2], output)
    }

    func testRetriesRespectDemand() throws {
        let scheduler = DispatchQueue.test

        var output: [Int] = []
        let subscriber = AnySubscriber<Int, Err>(
            receiveSubscription: { (subscription: Subscription) in
                subscription.request(.max(1))
            },
            receiveValue: { (value: Int) -> Subscribers.Demand in
                output.append(value)
                return .none
            },
            receiveCompletion: { _ in XCTFail() }
        )

        [1, 2, 3]
            .publisher
            .failOnOutputIndex([0, 1, 2], error: .one)
            .retryIf(
                { $0 == .one },
                after: .seconds(1),
                scheduler: scheduler
            )
            .receive(subscriber: subscriber)

        scheduler.advance(by: .seconds(2))
        XCTAssertTrue(output.isEmpty)

        scheduler.run()
        XCTAssertEqual([1], output)
    }
}

private typealias Pub = AnyPublisher<Int, Err>

private enum Err: Error, Equatable {
    case one
    case two
}

private extension Publisher where Output == Int, Failure == Never {
    func failOnOutputIndex(_ indexes: [Int], error: Err) -> AnyPublisher<Int, Err> {
        var index = 0
        return tryMap { (int: Int) throws -> Int in
            defer { index += 1 }
            if indexes.contains(index) {
                throw error
            } else {
                return int
            }
        }
        .mapError { $0 as! Err }
        .eraseToAnyPublisher()
    }
}
