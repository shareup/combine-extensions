import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class InputStreamPublisherTests: XCTestCase {
    func testInputStreamPublisherWithData() throws {
        let data = Data("Hello!".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
            [111, 33],
        ]

        let ex = InputStreamPublisher(data: data, maxChunkLength: 2)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithLessData() throws {
        let data = Data("Hello".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
            [111],
        ]

        let ex = InputStreamPublisher(data: data, maxChunkLength: 2)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithValidURL() throws {
        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("testInputStreamPublisherWithValidURL-\(arc4random())")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("text.txt")
        try Data("Hello!".utf8).write(to: url, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let expectedOutput: [[UInt8]] = [
            [72, 101, 108],
            [108, 111, 33],
        ]

        let ex = InputStreamPublisher(url: url, maxChunkLength: 3)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherFailsForInvalidURL() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("this-folder-does-not-exist")
            .appendingPathComponent("this-file-does-not-exist-\(arc4random()).dat")

        let ex = InputStreamPublisher(url: url, maxChunkLength: 1)
            .expectAnyFailure(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherOnlyProvidesAsManyChunksAsRequested() throws {
        let data = Data("Hello!".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
        ]

        var receivedOutput: [[UInt8]] = []

        let outputEx = expectation(description: "Should have received two chunks")
        outputEx.expectedFulfillmentCount = 2

        let noCompletionEx = expectation(description: "Should not have received a completion")
        noCompletionEx.isInverted = true

        let sub = AnySubscriber<[UInt8], Error>(
            receiveSubscription: { $0.request(.max(2)) },
            receiveValue: { bytes in
                receivedOutput.append(bytes)
                outputEx.fulfill()
                return .none
            },
            receiveCompletion: { _ in noCompletionEx.fulfill() }
        )

        let pub = InputStreamPublisher(data: data, maxChunkLength: 2)
        pub.subscribe(sub)

        wait(for: [outputEx], timeout: 2)
        wait(for: [noCompletionEx], timeout: 0.1)

        XCTAssertEqual(expectedOutput, receivedOutput)
    }

    func testInputStreamDoesNotReceiveFinishWhenCancelled() throws {
        class Box { var subscription: AnyObject? }
        let box = Box()

        let data = Data("Hello!".utf8)

        let expectedOutput: [UInt8] = [72, 101]

        let outputEx = expectation(description: "Should have received one chunk")
        let completionEx = expectation(description: "Should not have finished")
        completionEx.isInverted = true

        let subscriber = AnySubscriber<[UInt8], Error>(
            receiveSubscription: { sub in
                box.subscription = sub as AnyObject
                sub.request(.max(1))
            },
            receiveValue: { bytes in
                XCTAssertEqual(expectedOutput, bytes)
                outputEx.fulfill()
                (box.subscription as? Cancellable)?.cancel()
                return .max(1)
            },
            receiveCompletion: { _ in completionEx.fulfill() }
        )

        let pub = InputStreamPublisher(data: data, maxChunkLength: 2)
        pub.subscribe(subscriber)

        wait(for: [outputEx], timeout: 2)
        wait(for: [completionEx], timeout: 0.1)
    }
}
