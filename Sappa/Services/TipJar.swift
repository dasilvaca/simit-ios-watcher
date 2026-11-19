import Foundation
import Observation
import StoreKit

/// "Apoyar el proyecto": consumable in-app purchases (never an external donation link on iOS).
/// Create these products in App Store Connect; amounts are still an open question.
@MainActor
@Observable
final class TipJar {
    enum State: Equatable { case loading, ready, unavailable, purchasing, thanks, failed }

    static var productIDs: [String] {
        let base = Bundle.main.bundleIdentifier ?? "sappa"
        return ["\(base).tip.small", "\(base).tip.medium", "\(base).tip.large"]
    }

    private(set) var products: [Product] = []
    var state: State = .loading

    func load() async {
        state = .loading
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            state = products.isEmpty ? .unavailable : .ready
        } catch {
            state = .unavailable
        }
    }

    func buy(_ product: Product) async {
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                state = .thanks
            case .success(.unverified):
                state = .failed
            case .userCancelled, .pending:
                state = .ready
            @unknown default:
                state = .ready
            }
        } catch {
            state = .failed
        }
    }
}
