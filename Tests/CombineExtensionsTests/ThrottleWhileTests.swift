import Combine
import CombineExtensions
import XCTest

final class ThrottleWhileTests: XCTestCase {
    func testLatestStartsPublishingImmediately() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([0, 1, 2])

        subject.send(0)
        subject.send(1)
        subject.send(2)

        wait(for: [ex], timeout: 2)
    }

    func testEarliestStartsPublishingImmediately() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0, 1, 2])

        subject.send(0)
        subject.send(1)
        subject.send(2)

        wait(for: [ex], timeout: 2)
    }

    func testThrottledLatestOnlyPublishesAfterRegulatorIsFalse() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = CurrentValueSubject<Bool, Never>(true)

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([2])

        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)

        wait(for: [ex], timeout: 2)
    }

    func testThrottledEarliestOnlyPublishesAfterRegulatorIsFalse() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = CurrentValueSubject<Bool, Never>(true)

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0])

        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)

        wait(for: [ex], timeout: 2)
    }

    func testThrottleWhileWorksWithCustomErrorFailureType() throws {
        let subject = PassthroughSubject<Int, Error>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator.setFailureType(to: Error.self))
            .expectOutput([2])

        regulator.send(true)
        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)

        wait(for: [ex], timeout: 2)
    }

    func testLatestHandlesEngagingAndReleasingThrottle() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([0, 1, 4, 5])

        subject.send(0)
        subject.send(1)
//        regulator.send(false)
        regulator.send(true)
        subject.send(2)
        subject.send(3)
        subject.send(4)
        regulator.send(false)
        regulator.send(true)
        regulator.send(false)
        subject.send(5)

        wait(for: [ex], timeout: 2)
    }

    func testEarliestHandlesEngagingAndReleasingThrottle() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0, 1, 2, 5])

        subject.send(0)
        subject.send(1)
        regulator.send(true)
        subject.send(2)
        subject.send(3)
        subject.send(4)
        regulator.send(false)
        regulator.send(true)
        regulator.send(false)
        subject.send(5)

        wait(for: [ex], timeout: 2)
    }

    func testLatestDoesNotPublishAfterCompletion() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([2, 3], expectToFinish: true)

        regulator.send(true)
        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)
        subject.send(3)
        subject.send(completion: .finished)
        subject.send(4)

        wait(for: [ex], timeout: 2)
    }

    func testEarliestDoesNotPublishAfterCompletion() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0, 3], expectToFinish: true)

        regulator.send(true)
        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)
        subject.send(3)
        subject.send(completion: .finished)
        subject.send(4)

        wait(for: [ex], timeout: 2)
    }

    func testLatestDoesNotPublishAfterRegulatorCompletes() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([2, 3])

        regulator.send(true)
        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)
        subject.send(3)
        regulator.send(completion: .finished)
        subject.send(4)

        wait(for: [ex], timeout: 2)
    }

    func testEarliestDoesNotPublishAfterRegulatorCompletes() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0, 3])

        regulator.send(true)
        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)
        subject.send(3)
        regulator.send(completion: .finished)
        subject.send(4)

        wait(for: [ex], timeout: 2)
    }

    func testLatestPublishesWhenRegulatorFiresFromSink() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()
        var values = [Int]()

        let subscription = subject
            .throttle(while: regulator, latest: true)
            .removeDuplicates()
            .sink { value in
                values.append(value)
                regulator.send(true)
            }

        subject.send(1)
        subject.send(2)
        regulator.send(false)

        defer { subscription.cancel() }

        XCTAssertEqual(values, [1, 2])
    }
    
    func testEarliestPublishesWhenRegulatorFiresFromSink() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()
        var values = [Int]()

        let subscription = subject
            .throttle(while: regulator, latest: false)
            .removeDuplicates()
            .sink { value in
                values.append(value)
                regulator.send(true)
            }

        subject.send(1)
        subject.send(2)
        regulator.send(false)

        defer { subscription.cancel() }

        XCTAssertEqual(values, [1, 2])
    }
    
    func testLatestFlippingRegulatorDoesNotResendSameEmission() throws {
        func pause() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        
        let subject = PassthroughSubject<String, Never>()
        let regulator = PassthroughSubject<Bool, Never>()
        var values = [String]()
       
        let firstEx = expectation(description: "received first emission")
        let compEx = expectation(description: "stream is completed")
        let sub = subject
            .throttle(while: regulator, latest: true)
            .enumerated()
            .sink(
                receiveValue: { i, value in
                    values.append(value)
                    if i == 0 { firstEx.fulfill() }
                },
                receiveCompletion: { _ in compEx.fulfill() }
            )
        defer { sub.cancel() }
        
        subject.send("one")
        wait(for: [firstEx], timeout: 2)
        XCTAssertEqual(["one"], values)
        
        regulator.send(true)
        regulator.send(false)
        regulator.send(true)
        regulator.send(false)
        
        pause()
        
        XCTAssertEqual(["one"], values)
        
        subject.send("one")
        
        regulator.send(true)
        subject.send("two")
        subject.send("three")
        subject.send("four")
        regulator.send(false)
        
        subject.send(completion: .finished)
        wait(for: [compEx], timeout: 2)
        
        XCTAssertEqual(["one", "one", "four"], values)
    }
    
    func testEarliestFlippingRegulatorDoesNotResendSameEmission() throws {
        func pause() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        
        let subject = PassthroughSubject<String, Never>()
        let regulator = PassthroughSubject<Bool, Never>()
        var values = [String]()
       
        let firstEx = expectation(description: "received first emission")
        let compEx = expectation(description: "stream is completed")
        let sub = subject
            .throttle(while: regulator, latest: false)
            .enumerated()
            .sink(
                receiveValue: { i, value in
                    values.append(value)
                    if i == 0 { firstEx.fulfill() }
                },
                receiveCompletion: { _ in compEx.fulfill() }
            )
        defer { sub.cancel() }
        
        subject.send("one")
        wait(for: [firstEx], timeout: 2)
        XCTAssertEqual(["one"], values)
        
        regulator.send(true)
        regulator.send(false)
        regulator.send(true)
        regulator.send(false)
        
        pause()
        
        XCTAssertEqual(["one"], values)
        
        subject.send("one")
        
        regulator.send(true)
        subject.send("two")
        subject.send("three")
        subject.send("four")
        regulator.send(false)
        
        subject.send(completion: .finished)
        wait(for: [compEx], timeout: 2)
        
        XCTAssertEqual(["one", "one", "two"], values)
    }
}
