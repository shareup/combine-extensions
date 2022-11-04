import Combine
import CombineExtensions
import XCTest

final class ThrottleWhileTests: XCTestCase {
    func testLatestDoesNotPublishUntilRegulatorIsSetToFalse() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: true)
            .expectOutput([2])

        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)

        wait(for: [ex], timeout: 2)
    }

    func testEarliestDoesNotPublishUntilRegulatorIsSetToFalse() throws {
        let subject = PassthroughSubject<Int, Never>()
        let regulator = PassthroughSubject<Bool, Never>()

        let ex = subject
            .throttle(while: regulator, latest: false)
            .expectOutput([0])

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
            .expectOutput([1, 4, 5])

        subject.send(0)
        subject.send(1)
        regulator.send(false)
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
            .expectOutput([0, 2, 5])

        subject.send(0)
        subject.send(1)
        regulator.send(false)
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

        subject.send(0)
        subject.send(1)
        subject.send(2)
        regulator.send(false)
        subject.send(3)
        regulator.send(completion: .finished)
        subject.send(4)

        wait(for: [ex], timeout: 2)
    }
}
