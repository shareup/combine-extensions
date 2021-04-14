import Combine
import Synchronized

public extension Cancellable {
    func store(in store: SingleSubscriptionStore) {
        store.store(subscription: AnyCancellable(self))
    }
}

public class SingleSubscriptionStore: Hashable {
    private var subscription: AnyCancellable?
    private let lock = Lock()

    public init(_ subscription: AnyCancellable? = nil) {
        self.subscription = subscription
    }

    public func store(subscription: AnyCancellable) {
        lock.locked { self.subscription = subscription }
    }

    @discardableResult
    public func removeSubscription() -> AnyCancellable? {
        lock.locked {
            let sub = subscription
            subscription = nil
            return sub
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: SingleSubscriptionStore, rhs: SingleSubscriptionStore) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
