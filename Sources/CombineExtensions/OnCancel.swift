import Foundation
import Combine

public extension Cancellable {
    func onCancel(_ block: @escaping () -> Void) -> AnyCancellable {
        AnyCancellable { [self] in
            self.cancel()
            block()
        }
    }
}
