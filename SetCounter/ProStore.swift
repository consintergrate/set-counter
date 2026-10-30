import StoreKit
import SwiftUI
import WidgetKit

/// The three ways to buy Pro. Monthly and yearly renew in one subscription group;
/// lifetime is a one-time purchase.
enum ProPlan: String, CaseIterable, Identifiable {
    case yearly, monthly, lifetime

    var id: String { rawValue }
    var productID: String { "com.andykim.SetCounter.pro.\(rawValue)" }

    init?(productID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    var title: LocalizedStringKey {
        switch self {
        case .yearly: "연간"
        case .monthly: "월간"
        case .lifetime: "평생"
        }
    }

    var isSubscription: Bool { self != .lifetime }

    /// The planned Korean prices, shown only in debug builds while the App Store has no products.
    var referencePrice: Decimal {
        switch self {
        case .yearly: 22000
        case .monthly: 2900
        case .lifetime: 49000
        }
    }

    /// Lifetime wins over yearly over monthly when more than one is owned.
    var rank: Int {
        switch self {
        case .lifetime: 3
        case .yearly: 2
        case .monthly: 1
        }
    }

    /// How much less a year costs than twelve months, in whole percent.
    static func yearlySavings(yearly: Decimal, monthly: Decimal) -> Int? {
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else { return nil }
        let ratio = NSDecimalNumber(decimal: (twelveMonths - yearly) / twelveMonths).doubleValue
        return Int((ratio * 100).rounded())
    }
}

/// What Pro unlocks, grouped the way the paywall lists it.
enum ProFeature: String, CaseIterable, Identifiable {
    case stats, reports, watch, routines, diet, data, personalize

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .stats: "자세한 통계"
        case .reports: "지난 리포트와 비교"
        case .watch: "Apple Watch 앱"
        case .routines: "내 루틴과 다음 목표"
        case .diet: "식단·체중 전체 기록"
        case .data: "데이터 도구"
        case .personalize: "위젯과 테마"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .stats: "운동별 1RM·볼륨 추이, 부위 밸런스, 운동 잔디, 개인 기록 보드, 유산소 차트"
        case .reports: "지난 날짜·지난 12주 리포트, 지난주 대비 증감"
        case .watch: "손목에서 보는 실시간 심박수, 휴식이 끝나면 손목 알림"
        case .routines: "부위별 내 루틴 편집, 다음 무게·횟수 자동 추천"
        case .diet: "지난 날짜 식단, 내 음식 저장, 체중 1년 추세·BMI"
        case .data: "CSV 내보내기·가져오기, 운동 이름 합치기·부위 지정"
        case .personalize: "칼로리 위젯, 잠금 화면 위젯, 화면 모드·강조 색"
        }
    }

    var systemImage: String {
        switch self {
        case .stats: "chart.xyaxis.line"
        case .reports: "doc.text.magnifyingglass"
        case .watch: "applewatch"
        case .routines: "list.bullet.clipboard"
        case .diet: "fork.knife"
        case .data: "tablecells"
        case .personalize: "paintpalette"
        }
    }

    var color: Color {
        switch self {
        case .stats: .blue
        case .reports: .teal
        case .watch: .red
        case .routines: .orange
        case .diet: .green
        case .data: .indigo
        case .personalize: .purple
        }
    }
}

/// Pro purchases through StoreKit 2. `isPro` starts from the last known answer, so a
/// Pro user isn't locked out for a moment at launch or while offline.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()
    nonisolated static let cacheKey = "proUnlocked"
    #if DEBUG
    /// Debug builds can turn Pro on without buying, to try the unlocked screens.
    nonisolated static let debugUnlockKey = "debugProUnlocked"
    #endif

    /// One owned product, as much of the transaction as the check needs.
    struct Entitlement {
        let productID: String
        var expiration: Date?
        var revoked = false
        var transactionID: UInt64?
    }

    enum PurchaseOutcome { case purchased, pending, cancelled }

    enum StoreError: LocalizedError {
        case unverified

        var errorDescription: String? {
            String(localized: "App Store에서 구매를 확인하지 못했어요. 잠시 후 '구매 복원'을 눌러 주세요.")
        }
    }

    private(set) var isPro: Bool
    private(set) var activePlan: ProPlan?
    /// When the current subscription renews or ends.
    private(set) var renewalDate: Date?
    /// The purchase behind Pro, for the refund request sheet.
    private(set) var transactionID: UInt64?
    /// nil until the App Store has answered, or for lifetime.
    private(set) var willRenew: Bool?
    private(set) var products: [ProPlan: Product] = [:]
    private(set) var isLoadingProducts = false
    private(set) var productsFailed = false
    /// The yearly plan's free week, for people who haven't had it yet.
    private(set) var trialEligible = true
    #if DEBUG
    var debugUnlocked: Bool {
        didSet {
            defaults.set(debugUnlocked, forKey: Self.debugUnlockKey)
            publish()
        }
    }
    #endif

    @ObservationIgnored private let defaults: UserDefaults
    /// The shared store keeps the widgets' copy current; test instances don't.
    @ObservationIgnored private let updatesWidgets: Bool
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, updatesWidgets: Bool = true) {
        self.defaults = defaults
        self.updatesWidgets = updatesWidgets
        isPro = defaults.bool(forKey: Self.cacheKey)
        #if DEBUG
        debugUnlocked = defaults.bool(forKey: Self.debugUnlockKey)
        if debugUnlocked { isPro = true }
        #endif
    }

    /// Called once at launch: picks up renewals, refunds, Ask to Buy approvals, and
    /// purchases made on another device.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let found = try await Product.products(for: ProPlan.allCases.map(\.productID))
            products = Dictionary(found.compactMap { product in ProPlan(productID: product.id).map { ($0, product) } },
                                  uniquingKeysWith: { first, _ in first })
            productsFailed = products.isEmpty
            if let subscription = products[.yearly]?.subscription {
                trialEligible = await subscription.isEligibleForIntroOffer
            }
            await updateRenewal()
        } catch {
            productsFailed = true
        }
    }

    /// A plan's price as a number, read back from the shown price: StoreKit testing reports
    /// won prices a thousand times too small in `price`, while `displayPrice` is right.
    func amount(_ plan: ProPlan) -> Decimal? {
        guard let product = products[plan] else { return nil }
        return (try? Decimal(product.displayPrice, format: product.priceFormatStyle)) ?? product.price
    }

    /// Finishes what `PurchaseAction` returned and unlocks on success.
    func complete(_ result: Product.PurchaseResult) async throws -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw StoreError.unverified }
            await transaction.finish()
            await refreshEntitlements(adding: transaction)
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Asks the App Store for this Apple Account's purchases; it may ask to sign in.
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    /// `latest` is a purchase that just went through: StoreKit can take a moment to list
    /// it among the current entitlements, and Pro should open right away.
    func refreshEntitlements(adding latest: StoreKit.Transaction? = nil) async {
        var owned: [Entitlement] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            owned.append(Entitlement(transaction))
        }
        if let latest, !owned.contains(where: { $0.productID == latest.productID }) {
            owned.append(Entitlement(latest))
        }
        let best = Self.bestPlan(owned)
        activePlan = best?.plan
        renewalDate = best?.entitlement.expiration
        transactionID = best?.entitlement.transactionID
        defaults.set(best != nil, forKey: Self.cacheKey)
        publish()
        await updateRenewal()
    }

    /// The plan that unlocks Pro: refunded and lapsed purchases don't count.
    static func bestPlan(_ owned: [Entitlement], now: Date = Date()) -> (plan: ProPlan, entitlement: Entitlement)? {
        owned
            .compactMap { item -> (plan: ProPlan, entitlement: Entitlement)? in
                guard !item.revoked, let plan = ProPlan(productID: item.productID) else { return nil }
                if let expiration = item.expiration, expiration <= now { return nil }
                return (plan, item)
            }
            .max { $0.plan.rank < $1.plan.rank }
    }

    private func updateRenewal() async {
        guard let plan = activePlan, plan.isSubscription,
              let statuses = try? await products[plan]?.subscription?.status else {
            willRenew = nil
            return
        }
        willRenew = statuses.contains { status in
            if case .verified(let info) = status.renewalInfo { return info.willAutoRenew }
            return false
        }
    }

    private func publish() {
        var unlocked = defaults.bool(forKey: Self.cacheKey)
        #if DEBUG
        if debugUnlocked { unlocked = true }
        #endif
        guard updatesWidgets else {
            isPro = unlocked
            return
        }
        let changed = unlocked != isPro || unlocked != ProStatus.isUnlocked
        isPro = unlocked
        if changed {
            ProStatus.set(unlocked)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension ProStore.Entitlement {
    init(_ transaction: StoreKit.Transaction) {
        self.init(productID: transaction.productID, expiration: transaction.expirationDate,
                  revoked: transaction.revocationDate != nil, transactionID: transaction.id)
    }
}
