import StoreKit
import SwiftUI

enum ProStyle {
    /// Deep orange to deep pink: white text on either end stays above 5:1.
    static let colors: [Color] = [Color(hex: 0xC2410C), Color(hex: 0xBE185D)]
    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// For orange text and small icons on the light cards.
    static let text = Color.orange.readable
}

/// Small "PRO" tag next to anything that needs Pro.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ProStyle.gradient, in: Capsule())
            .accessibilityLabel(Text("Pro 기능"))
    }
}

extension View {
    /// Pro content stays in place, blurred, behind a button that opens the paywall.
    func proLocked(_ feature: ProFeature) -> some View {
        modifier(ProLockModifier(feature: feature))
    }

    func proPaywall(_ feature: Binding<ProFeature?>) -> some View {
        sheet(item: feature) { ProPaywallView(feature: $0) }
    }
}

private struct ProLockModifier: ViewModifier {
    let feature: ProFeature
    @State private var showingPaywall = false
    private let store = ProStore.shared

    func body(content: Content) -> some View {
        if store.isPro {
            content
        } else {
            content
                .frame(minHeight: 130)
                .blur(radius: 6)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(ProStyle.gradient)
                            .accessibilityHidden(true)
                        Text(feature.title).font(.subheadline.bold())
                        Button("Pro로 보기") { showingPaywall = true }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(ProStyle.colors[0])
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .sheet(isPresented: $showingPaywall) { ProPaywallView(feature: feature) }
        }
    }
}

/// A form row for a Pro-only action: opens the paywall instead.
struct ProLockedButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let feature: ProFeature

    @State private var showingPaywall = false

    var body: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title).foregroundStyle(Color.primary)
                }
                Spacer()
                ProBadge()
            }
        }
        .sheet(isPresented: $showingPaywall) { ProPaywallView(feature: feature) }
    }
}

/// The top row in settings.
struct ProSettingsLabel: View {
    private let store = ProStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(ProStyle.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("세트 카운터 Pro").font(.body.weight(.semibold))
                Text(store.isPro ? "사용 중이에요" : "자세한 통계, Apple Watch 앱, 내 루틴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.isPro {
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(ProStyle.text).accessibilityHidden(true)
            }
        }
    }
}

/// What Pro includes and the three plans. Opens as a sheet from a locked feature
/// (that feature listed first) or is pushed from settings.
struct ProPaywallView: View {
    var feature: ProFeature?
    var isSheet = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @AppStorage("hapticsOn") private var hapticsOn = true
    @State private var selected = ProPlan.yearly
    @State private var purchasing = false
    @State private var restoring = false
    @State private var managingSubscription = false
    @State private var requestingRefund = false
    @State private var message: String?
    @State private var purchasedCount = 0

    private let store = ProStore.shared

    var body: some View {
        if isSheet {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                    }
            }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if store.isPro {
                    activeCard
                } else if let feature {
                    highlight(feature)
                }
                featureList
                if !store.isPro {
                    VStack(spacing: 10) {
                        ForEach(ProPlan.allCases) { planCard($0) }
                    }
                    purchaseSection
                }
                links
                #if DEBUG
                debugCard
                #endif
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isSheet ? "" : String(localized: "세트 카운터 Pro"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
        .manageSubscriptionsSheet(isPresented: $managingSubscription)
        .refundRequestSheet(for: store.transactionID ?? 0, isPresented: $requestingRefund)
        .sensoryFeedback(trigger: purchasedCount) { _, _ in hapticsOn ? .success : nil }
        .alert("세트 카운터 Pro", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(ProStyle.gradient, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .pink.opacity(0.3), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("세트 카운터 Pro").font(.title.bold())
            Text(store.isPro
                 ? "Pro를 쓰고 있어요. 응원해 줘서 고마워요!"
                 : "운동 기록은 그대로 무료예요.\nPro는 기록을 더 깊이 보고, 내 방식대로 관리하게 해줘요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, isSheet ? 0 : 8)
    }

    private func highlight(_ feature: ProFeature) -> some View {
        HStack(spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.title2)
                .foregroundStyle(feature.color)
                .frame(width: 48, height: 48)
                .background(feature.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pro에서 쓸 수 있는 기능이에요").font(.caption.bold()).foregroundStyle(ProStyle.text)
                Text(feature.title).font(.headline)
                Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ProStyle.gradient, lineWidth: 1.5))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ProFeature.allCases.filter { $0 != feature || store.isPro }) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(item.color)
                        .frame(width: 32, height: 32)
                        .background(item.color.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.bold())
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if store.isPro {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityLabel(Text("사용 중"))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var activeCard: some View {
        VStack(spacing: 12) {
            Label(activeTitle, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(ProStyle.text)
            if let date = store.renewalDate {
                Text(store.willRenew == false
                     ? String(localized: "\(date.formatted(date: .long, time: .omitted))에 끝나요")
                     : String(localized: "\(date.formatted(date: .long, time: .omitted))에 갱신돼요"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if store.activePlan?.isSubscription == true {
                    Button("구독 관리") { managingSubscription = true }
                }
                if store.transactionID != nil {
                    Button("환불 요청") { requestingRefund = true }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var activeTitle: String {
        switch store.activePlan {
        case .yearly: String(localized: "연간 구독 중")
        case .monthly: String(localized: "월간 구독 중")
        case .lifetime: String(localized: "평생 이용권")
        case nil: String(localized: "Pro 사용 중")
        }
    }

    private func planCard(_ plan: ProPlan) -> some View {
        let isSelected = selected == plan
        return Button {
            selected = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(ProStyle.text) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.headline)
                    let tags = tags(for: plan)
                    if !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.bold())
                                    .foregroundStyle(ProStyle.text)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(priceLine(plan)).font(.headline).monospacedDigit()
                    Text(subPriceLine(plan)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? AnyShapeStyle(ProStyle.gradient) : AnyShapeStyle(Color.clear), lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { await buy(selected) }
            } label: {
                ZStack {
                    if purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(buttonTitle).font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(ProStyle.gradient, in: Capsule())
                .opacity(store.products[selected] == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(purchasing || store.products[selected] == nil)

            if store.products.isEmpty, !store.isLoadingProducts {
                VStack(spacing: 6) {
                    #if DEBUG
                    Text("개발 빌드라 App Store에 상품이 아직 없어요. Xcode에서 실행하면 StoreKit 테스트 결제를 해볼 수 있어요.")
                    #else
                    Text("App Store에서 가격을 불러오지 못했어요.")
                    #endif
                    Button("다시 시도") { Task { await store.loadProducts() } }
                        .font(.subheadline.bold())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Text(finePrint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var links: some View {
        HStack(spacing: 16) {
            Button(restoring ? String(localized: "확인 중…") : String(localized: "구매 복원")) {
                Task { await restore() }
            }
            .disabled(restoring)
            NavigationLink("이용약관") { LegalDocumentView(document: .terms) }
            NavigationLink("개인정보 처리방침") { LegalDocumentView(document: .privacy) }
        }
        .font(.caption.weight(.semibold))
    }

    #if DEBUG
    private var debugCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("테스트용 Pro 켜기", isOn: $store.debugUnlocked)
                .font(.subheadline.bold())
            Text("개발 빌드에만 있어요. 결제 없이 Pro 화면을 확인할 때 써요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    #endif

    // MARK: Text

    private func tags(for plan: ProPlan) -> [String] {
        switch plan {
        case .yearly:
            var tags: [String] = []
            if store.trialEligible { tags.append(String(localized: "7일 무료")) }
            if let savings = ProPlan.yearlySavings(yearly: price(.yearly), monthly: price(.monthly)) {
                // Against paying monthly for a year, not a sale price.
                tags.append(String(localized: "월간보다 \(savings)% 저렴"))
            }
            return tags
        case .monthly, .lifetime:
            return []
        }
    }

    private func price(_ plan: ProPlan) -> Decimal {
        store.amount(plan) ?? plan.referencePrice
    }

    private func formatted(_ amount: Decimal, like plan: ProPlan) -> String {
        if let product = store.products[plan] { return amount.formatted(product.priceFormatStyle) }
        #if DEBUG
        return amount.formatted(.currency(code: "KRW"))
        #else
        return "–"
        #endif
    }

    private func priceLine(_ plan: ProPlan) -> String {
        let price = store.products[plan]?.displayPrice ?? formatted(plan.referencePrice, like: plan)
        switch plan {
        case .yearly: return String(localized: "\(price)/년")
        case .monthly: return String(localized: "\(price)/월")
        case .lifetime: return price
        }
    }

    private func subPriceLine(_ plan: ProPlan) -> String {
        switch plan {
        case .yearly: String(localized: "월 \(formatted(price(.yearly) / 12, like: .yearly))꼴")
        case .monthly: String(localized: "언제든 해지")
        case .lifetime: String(localized: "한 번 결제")
        }
    }

    private var buttonTitle: String {
        switch selected {
        case .yearly: store.trialEligible ? String(localized: "7일 무료로 시작하기") : String(localized: "연간 구독 시작하기")
        case .monthly: String(localized: "월간 구독 시작하기")
        case .lifetime: String(localized: "평생 이용권 구매하기")
        }
    }

    /// The renewal terms App Review asks to see next to the button.
    private var finePrint: String {
        let price = store.products[selected]?.displayPrice ?? formatted(selected.referencePrice, like: selected)
        let cancel = String(localized: "끝나기 24시간 전까지 iPhone 설정 → Apple 계정 → 구독에서 해지하면 더 결제되지 않아요.")
        switch selected {
        case .yearly where store.trialEligible:
            return String(localized: "7일 무료 체험이 끝나면 연 \(price)이 결제되고 매년 자동으로 갱신돼요.") + " " + cancel
        case .yearly:
            return String(localized: "연 \(price)이 결제되고 매년 자동으로 갱신돼요.") + " " + cancel
        case .monthly:
            return String(localized: "월 \(price)이 결제되고 매달 자동으로 갱신돼요.") + " " + cancel
        case .lifetime:
            return String(localized: "한 번 결제하면 계속 쓸 수 있어요. 같은 Apple 계정의 다른 기기에서는 '구매 복원'을 눌러 주세요.")
        }
    }

    // MARK: Actions

    private func buy(_ plan: ProPlan) async {
        guard let product = store.products[plan] else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await purchase(product)
            switch try await store.complete(result) {
            case .purchased:
                purchasedCount += 1
                if isSheet {
                    // A beat to feel the success, then back to the feature that's now open.
                    try? await Task.sleep(for: .seconds(0.6))
                    dismiss()
                }
            case .pending:
                message = String(localized: "구매 승인을 기다리고 있어요. 승인되면 Pro가 자동으로 켜져요.")
            case .cancelled:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await store.restore()
            message = store.isPro
                ? String(localized: "구매를 복원했어요. Pro가 켜졌어요.")
                : String(localized: "이 Apple 계정으로 산 Pro를 찾지 못했어요.")
        } catch StoreKitError.userCancelled {
            // Backed out of the sign-in prompt.
        } catch {
            message = error.localizedDescription
        }
    }
}
