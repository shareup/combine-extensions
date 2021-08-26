import Foundation
import Combine
import Synchronized

public extension Cancellable {
    func store(in store: SingleSubscriptionStore) {
        store.store(subscription: AnyCancellable(self))
    }
}

public final class SingleSubscriptionStore: Hashable {
    private let key = UUID().uuidString
    private let keyedSubscriptionStore = KeyedSubscriptionStore()

    public init(_ subscription: AnyCancellable? = nil) {
        if let sub = subscription {
            keyedSubscriptionStore.store(subscription: sub, forKey: key)
        }
    }

    public var isEmpty: Bool { keyedSubscriptionStore.isEmpty }

    public func store(subscription: AnyCancellable) {
        keyedSubscriptionStore.store(subscription: subscription, forKey: key)
    }

    @discardableResult
    public func removeSubscription() -> AnyCancellable? {
        keyedSubscriptionStore.removeSubscription(forKey: key)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: SingleSubscriptionStore, rhs: SingleSubscriptionStore) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
