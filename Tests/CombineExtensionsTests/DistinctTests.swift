import Combine
import CombineExtensions
import Synchronized
import XCTest

final class DistinctTests: XCTestCase {
    func testDistinctWithStringArraysPublisher() throws {
        let pub = [
            ["a", "b", "c"],
            ["a", "b", "c", "d"],
            ["b", "c", "d"],
        ]
        .publisher
        .distinct()

        let expected = [
            ["a", "b", "c"],
            ["d"],
        ]

        let ex = pub.expectOutput(expected)

        wait(for: [ex], timeout: 2)
    }

    func testDistinctWithNumberArraysPublisher() throws {
        let pub = [
            [1, 2, 3],
            [2, 3, 4, 5, 6],
            [4, 5, 7],
        ]
        .publisher
        .distinct()

        let expected = [
            [1, 2, 3],
            [4, 5, 6],
            [7],
        ]

        let ex = pub.expectOutput(expected)

        wait(for: [ex], timeout: 2)
    }

    func testDistinctWithStructArraysPublisher() throws {
        struct WWDC: Hashable {
            let year: Int
        }

        let pub = [
            [WWDC(year: 2016), WWDC(year: 2017), WWDC(year: 2015)],
            [WWDC(year: 2015), WWDC(year: 2017), WWDC(year: 2018), WWDC(year: 2014)],
            [WWDC(year: 2014), WWDC(year: 2020), WWDC(year: 2021)],
        ].publisher.distinct()

        let expected = [
            [WWDC(year: 2016), WWDC(year: 2017), WWDC(year: 2015)],
            [WWDC(year: 2018), WWDC(year: 2014)],
            [WWDC(year: 2020), WWDC(year: 2021)],
        ]

        let ex = pub.expectOutput(expected)

        wait(for: [ex], timeout: 2)
    }

    func testDistinctWithTransformer() throws {
        struct WWDC: Equatable {
            let id: String
            let year: Int

            init(_ year: Int) {
                id = String(year)
                self.year = year
            }
        }

        let pub = [
            [WWDC(2016), WWDC(2017), WWDC(2015)],
            [WWDC(2015), WWDC(2017), WWDC(2018), WWDC(2014)],
            [WWDC(2014), WWDC(2020), WWDC(2021)],
        ].publisher.distinct(using: { $0.id })

        let expected = [
            [WWDC(2016), WWDC(2017), WWDC(2015)],
            [WWDC(2018), WWDC(2014)],
            [WWDC(2020), WWDC(2021)],
        ]

        let ex = pub.expectOutput(expected)

        wait(for: [ex], timeout: 2)
    }

    func testDistinctWithDictArraysPublisher() throws {
        let dicts: [[[String: AnyHashable]]] = [
            [["first": 1], ["second": "2"], ["third": 3.0]],
            [["first": 1], ["third": 3.0], ["fourth": Int64(4)]],
            [["first": 1], ["fifth": Double(5)]],
        ]

        let pub = dicts
            .publisher
            .distinct()

        let expected: [[[String: AnyHashable]]] = [
            [["first": 1], ["second": "2"], ["third": 3.0]],
            [["fourth": Int64(4)]],
            [["fifth": Double(5)]],
        ]

        let ex = pub.expectOutput(expected)

        wait(for: [ex], timeout: 2)
    }

    func testDistinctConsecutivenessWithPassthroughSubject() throws {
        let queue = DispatchQueue(
            label: "global.concurrent.queue",
            qos: .background,
            attributes: .concurrent
        )

        let subject = PassthroughSubject<[Int], Error>()
        let input: [[Int]] = (0 ... 1000).map { _ in
            (0 ... Int.random(in: 0 ... 30)).map { _ in Int.random(in: 0 ... 1000) }
        }

        let expected = Set(input.flatMap { $0 })

        let ex1 = expectation(description: "No duplicate events")
        let ex2 = expectation(description: "No duplicate values")
        let ex3 = expectation(description: "Expected set equals collected")

        let sub = subject
            .distinct()
            .replaceError(with: [])
            .collect()
            .sink { receivedValues in
                let uniqueReceivedValues = Set(receivedValues)
                if receivedValues.count == uniqueReceivedValues.count { ex1.fulfill() }
                else {
                    XCTFail(
                        "Received \(receivedValues.count) events, of which only \(uniqueReceivedValues.count) are unique"
                    )
                }

                let receivedIntegers = receivedValues.flatMap { $0 }
                let uniqueReceivedIntegers = Set(receivedIntegers)

                if receivedIntegers.count == uniqueReceivedIntegers.count { ex2.fulfill() }
                else {
                    XCTFail(
                        "Received \(receivedIntegers.count) values, of which only \(uniqueReceivedIntegers.count) are unique"
                    )
                }

                if uniqueReceivedIntegers == expected { ex3.fulfill() }
                else { XCTFail("Received set of elements does not equal expected") }
            }

        let lastIndex = input.count - 1
        input.enumerated().forEach { i, v in
            queue.async {
                subject.send(v)
                if i == lastIndex { subject.send(completion: .finished) }
            }
        }

        defer { sub.cancel() }

        wait(for: [ex1, ex2, ex3], timeout: 2)
    }
}
