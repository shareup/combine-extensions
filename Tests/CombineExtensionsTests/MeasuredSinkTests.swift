import XCTest
import Combine
import CombineExtensions

final class MeasuredSinkTests: XCTestCase {
    func testDoesNotPublishWithoutDemand() throws {
        let ex = expectation(description: "Should not have received value")
        ex.isInverted = true

        let pub = [1, 2, 3].publisher
        let sub = pub.measuredSink { _ in
            ex.fulfill()
            return .none
        }
        defer { sub.cancel() }

        wait(for: [ex], timeout: 0.1)
    }

    func testPublishesInitialDemand() throws {
        let ex = expectation(description: "Should have received one value")

        let pub = [1, 2, 3].publisher
        let sub = pub.measuredSink(initialDemand: .max(1)) { value in
            XCTAssertEqual(1, value)
            ex.fulfill()
            return .none
        }
        defer { sub.cancel() }

        wait(for: [ex], timeout: 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    func testPublishesAfterRequestDemand() throws {
        let ex = expectation(description: "Should have received value")
        ex.expectedFulfillmentCount = 2

        let pub = [1, 2, 3].publisher
        let sub = pub.measuredSink { _ in
            ex.fulfill()
            return .none
        }
        defer { sub.cancel() }

        sub.request(demand: .max(2))
        wait(for: [ex], timeout: 2)
    }

    func testDoesNotPublishAfterCancelling() throws {
        let ex = expectation(description: "Should have received value")

        let pub = [1, 2, 3].publisher
        let sub = pub.measuredSink { _ in
            ex.fulfill()
            return .none
        }

        sub.request(demand: .max(1))
        wait(for: [ex], timeout: 2)

        sub.cancel()
        sub.request(demand: .max(1))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    func testDoesNotOverflowStack() throws {
        let count = 1_000

        let ex = expectation(description: "Should have received value")
        ex.expectedFulfillmentCount = count

        struct Iter: IteratorProtocol {
            private var int = 0
            mutating func next() -> Int? {
                int += 1
                return int
            }
        }

        let sub = AnySequence(Iter.init)
            .publisher
            .measuredSink { (value: Int) -> Subscribers.Demand in
                ex.fulfill()
                return .none
            }
        defer { sub.cancel() }

        sub.request(demand: .max(count))
        wait(for: [ex], timeout: 10 * 60)
    }
}
