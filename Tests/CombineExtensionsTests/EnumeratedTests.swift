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

    func testEnumeratedWithInputStreamPublisher() throws {
        let data = Data("Hello".utf8)
        let pub = InputStreamPublisher(
            data: data,
            maxChunkLength: 2
        )
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
