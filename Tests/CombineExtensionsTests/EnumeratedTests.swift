import XCTest
import Combine
import CombineExtensions

final class EnumeratedTests: XCTestCase {
    func testEnumeratedWithArrayPublisher() throws {
        let pub = [10, 11, 12, 13, 14, 15]
            .publisher
            .map { String($0) }
            .enumerated()

        var expected = (0, 10)
        let ex = pub.expectOutput(
            { (index, value) in
                XCTAssertEqual(expected.0, index)
                XCTAssertEqual(String(expected.1), value)
                expected = (expected.0 + 1, expected.1 + 1)
                return expected.0 >= 6 ? .finished : .moreExpected
            },
            expectToFinish: true
        )

        wait(for: [ex], timeout: 2)
    }

    func testEnumeratedWraps() throws {
        let pub = [1, 2, 3]
            .publisher
            .enumerated(startIndex: Int.max)

        var expected = [(Int.max, 1), (Int.min, 2), (Int.min + 1, 3)]
        let ex = pub
            .expectOutput { (index, number) in
                let expectedOutput = expected.removeFirst()
                XCTAssertEqual(expectedOutput.0, index)
                XCTAssertEqual(expectedOutput.1, number)

                return expected.isEmpty ? .finished : .moreExpected
            }

        wait(for: [ex], timeout: 2)
    }

    func testEnumeratedWithCustomStartIndexWithArrayPublisher() throws {
        let pub = [10, 11, 12, 13, 14, 15]
            .publisher
            .map { String($0) }
            .enumerated(startIndex: 100)

        var expected = (100, 10)
        let ex = pub.expectOutput(
            { (index, value) in
                XCTAssertEqual(expected.0, index)
                XCTAssertEqual(String(expected.1), value)
                expected = (expected.0 + 1, expected.1 + 1)
                return expected.0 >= 106 ? .finished : .moreExpected
            },
            expectToFinish: true
        )

        wait(for: [ex], timeout: 2)
    }

    func testEnumeratedWithArrayPublisherWithArraysAsOutput() throws {
        let matrix = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
        ]

        let pub = matrix
            .publisher
            .enumerated()

        let ex = pub.expectOutput(
            { (index, value) in
                XCTAssertEqual(matrix[index], value)
                return index == 2 ? .finished : .moreExpected
            },
            expectToFinish: true
        )

        wait(for: [ex], timeout: 2)
    }

    func testEnumeratedWithInputStreamPublisher() throws {
        let data = Data("Hello".utf8)
        let pub = Publishers.InputStream(data: data, maxChunkSize: 2)
            .enumerated()

        var expected = [
            (0, Array("He".utf8)),
            (1, Array("ll".utf8)),
            (2, Array("o".utf8)),
        ]
        let ex = pub.expectOutput(
            { (index, value) in
                let first = expected.removeFirst()
                XCTAssertEqual(first.0, index)
                XCTAssertEqual(first.1, value)
                return expected.isEmpty ? .finished : .moreExpected
            },
            expectToFinish: true
        )

        wait(for: [ex], timeout: 2)
    }
}
