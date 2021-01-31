import Combine
import Foundation

public extension Publisher {
    func sink(
        receiveValue: @escaping ((Output) -> Void),
        receiveCompletion: @escaping ((Subscribers.Completion<Failure>) -> Void)
    ) -> AnyCancellable {
        sink(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
    }
}

public extension Publisher where Output == Void {
    func sink(
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
    ) -> AnyCancellable {
        sink(receiveCompletion: receiveCompletion, receiveValue: {})
    }
}
