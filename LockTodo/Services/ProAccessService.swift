import Foundation
import StoreKit

/// Single source of truth for Pro entitlement across the app.
///
/// Freemium model: the app is fully usable free; Pro unlocks monthly insights
/// and advanced lock-screen widget styles. Offered as a subscription
/// (monthly / yearly) *and* a one-time lifetime unlock, so both recurring
/// revenue and subscription-averse users are captured. StoreKit 2, on-device
/// verification only — no receipt server needed for a solo app.
@MainActor
final class ProAccessService: ObservableObject {
    static let shared = ProAccessService()

    static let monthlyProductID = "com.jaeseok.LockTodo.pro.monthly"
    static let yearlyProductID = "com.jaeseok.LockTodo.pro.yearly"
    static let lifetimeProductID = "com.jaeseok.LockTodo.pro.lifetime"
    /// Display order in the paywall.
    static let allProductIDs = [yearlyProductID, monthlyProductID, lifetimeProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    /// The product ID currently mid-purchase, for per-button spinners.
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = observeTransactions()
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = Self.allProductIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            statusMessage = "상품 정보를 불러오지 못했습니다."
        }
    }

    func purchase(_ product: Product) async {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                statusMessage = "승인이 완료되면 Pro가 자동으로 활성화됩니다."
            case .userCancelled:
                break
            @unknown default:
                statusMessage = "구매 상태를 확인하지 못했습니다."
            }
        } catch {
            statusMessage = "구매를 완료하지 못했습니다."
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro { statusMessage = "복원할 Pro 구매가 없습니다." }
        } catch {
            statusMessage = "구매 복원에 실패했습니다."
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? verified(entitlement) else { continue }
            // currentEntitlements already excludes expired subscriptions, so a
            // hit on any of our product IDs (not revoked) means Pro is active.
            if Self.allProductIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let transaction = try? self?.verified(update) else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}

extension Product {
    /// "월" / "년" for subscriptions, nil for the lifetime non-consumable.
    var lockTodoPeriodSuffix: String? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .day: return "일"
        case .week: return "주"
        case .month: return period.value == 12 ? "년" : "월"
        case .year: return "년"
        @unknown default: return nil
        }
    }
}
