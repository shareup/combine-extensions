import Combine

public extension Publisher {
    func multicastLatest() -> some Publisher<Output, Failure> {
        map(Optional.some)
            .multicast({ CurrentValueSubject<Output?, Failure>(nil) })
            .autoconnect()
            .compactMap { $0 }
    }
}
