import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class MulticastLatestSubjectTests: XCTestCase {
    func testMulticastLatest() {
        let voidSubject = PassthroughSubject<Void, Never>()
        let intSubject = PassthroughSubject<Int, Never>()
        var mapCalledCount = 0
        
        let multicastedPublisher = voidSubject
            .map {
                mapCalledCount += 1
                return intSubject
            }
            .switchToLatest()
            .multicastLatest()
        
        let outputExpectation = multicastedPublisher.expectOutput([1, 2])

        voidSubject.send(())
        intSubject.send(1)
        intSubject.send(2)
        
        let expectation1 = expectation(description: "first subscriber")
        let subscription1 = multicastedPublisher.sink { value in
            XCTAssertEqual(value, 2)
            expectation1.fulfill()
        }
        defer { subscription1.cancel() }
        
        let expectation2 = expectation(description: "second subscriber")
        let subscription2 = multicastedPublisher.sink { value in
            XCTAssertEqual(value, 2)
            expectation2.fulfill()
        }
        defer { subscription2.cancel() }
        
        wait(for: [outputExpectation, expectation1, expectation2], timeout: 0.5)
        XCTAssertEqual(mapCalledCount, 1)
    }
}
