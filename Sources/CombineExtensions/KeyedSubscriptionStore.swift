import Combine
import Synchronized

public extension Cancellable {
    func store(in store: KeyedSubscriptionStore, key: String) {
        store.store(subscription: AnyCancellable(self), forKey: key)
    }
}

public final class KeyedSubscriptionStore: Hashable {
    private var subscriptions: [String: AnyCancellable]
    private let lock = Lock()

    public init(subscriptions: [String: AnyCancellable] = [:]) {
        self.subscriptions = subscriptions
    }

    public var isEmpty: Bool { lock.locked { subscriptions.isEmpty } }

    public func containsSubscription(forKey key: String) -> Bool {
        lock.locked { subscriptions[key] != nil }
    }

    public func store(subscription: AnyCancellable, forKey key: String) {
        lock.locked { subscriptions[key] = subscription }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        lock.locked { subscriptions.removeAll(keepingCapacity: keepCapacity) }
    }

    @discardableResult
    public func removeSubscription(forKey key: String) -> AnyCancellable? {
        lock.locked { subscriptions.removeValue(forKey: key) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: KeyedSubscriptionStore, rhs: KeyedSubscriptionStore) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
