import StoreKit
import SwiftUI

/// The privacy policy, terms of use, and refund policy, readable in the app and offline.
/// The privacy policy matches AppStore/PRIVACY_POLICY.md and the web page.
enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy, terms, refund

    var id: String { rawValue }

    struct Section: Identifiable {
        let title: String
        /// Paragraphs; ones starting with "• " are list items.
        let paragraphs: [String]
        var id: String { title }
    }

    static let effectiveDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 30).date ?? Date()

    var title: LocalizedStringKey {
        switch self {
        case .privacy: "개인정보 처리방침"
        case .terms: "이용약관"
        case .refund: "환불 정책"
        }
    }

    var systemImage: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .terms: "doc.text.fill"
        case .refund: "arrow.uturn.backward.circle.fill"
        }
    }

    var summary: String {
        switch self {
        case .privacy:
            String(localized: "세트 카운터는 개인정보를 수집하지 않고, 어떤 정보도 외부 서버로 보내지 않습니다. 모든 운동 기록은 사용자의 iPhone 안에만 저장됩니다.")
        case .terms:
            String(localized: "운동을 기록하는 기능은 무료이고, 일부 기능은 세트 카운터 Pro(유료)에서 쓸 수 있습니다. 앱이 보여주는 칼로리와 추천 값은 추정치이며 의학적 조언이 아닙니다.")
        case .refund:
            String(localized: "세트 카운터 Pro는 App Store에서 결제되고, 환불도 Apple이 처리합니다. 앱의 '환불 요청'이나 reportaproblem.apple.com에서 신청할 수 있습니다.")
        }
    }

    var sections: [Section] {
        switch self {
        case .privacy: Self.privacySections
        case .terms: Self.termsSections
        case .refund: Self.refundSections
        }
    }

    private static var privacySections: [Section] {
        [
            Section(title: String(localized: "1. 기기에 저장되는 정보"), paragraphs: [
                String(localized: "아래 정보는 사용자의 iPhone 안에만 저장되며, 개발자나 제3자에게 전송되지 않습니다."),
                String(localized: "• 운동 기록: 운동 이름, 무게, 반복 횟수, 세트 수, 운동 시간, 루틴 부위"),
                String(localized: "• 신체 정보와 목표: 몸무게, 키, 나이, 성별, 목표 체중, 걸음·활동·유산소 목표 (칼로리와 목표 계산에만 사용)"),
                String(localized: "• 심박수와 칼로리: 운동 중 측정·계산된 평균/최대 심박수와 추정 칼로리"),
                String(localized: "• 앱 설정: 루틴, 목표, 알림 시간, 테마 등"),
            ]),
            Section(title: String(localized: "2. 건강 앱(HealthKit) 데이터"), paragraphs: [
                String(localized: "사용자가 허용한 경우에만 다음을 이용합니다."),
                String(localized: "• 읽기: 심박수, 걸음 수, 활동 칼로리, 걷기·달리기·사이클·수영 거리, 체중, 섭취 칼로리, 그리고 다른 앱(나이키 런 클럽, 피트니스 등)이 저장한 운동 기록. 운동 중 칼로리 계산, 하루 칼로리·활동 목표, 유산소 기록, 코치 안내와 리포트를 기기 안에서 계산하고 보여주는 데에만 사용합니다."),
                String(localized: "• 쓰기: 마친 근력 운동과 소모 칼로리, 사용자가 직접 기록한 체중과 식사(음식 이름, 섭취 칼로리, 메모)를 건강 앱에 저장합니다."),
                String(localized: "HealthKit 데이터는 광고나 마케팅에 사용하지 않고, 판매하지 않으며, iCloud나 외부 서버에 저장하지 않습니다. 권한은 언제든지 iPhone 설정 → 건강 → 데이터 접근 및 기기에서 끌 수 있습니다."),
            ]),
            Section(title: String(localized: "3. 블루투스와 Apple Watch"), paragraphs: [
                String(localized: "블루투스 심박 센서(가슴 스트랩 등)에서 심박수를 받을 때만 블루투스를 사용합니다. Apple Watch 앱은 운동 중 심박수와 세트 진행 상황을 사용자의 iPhone과 직접 주고받으며, 워치에서 잰 근력 운동을 건강 앱에 저장합니다. 이 정보는 사용자의 기기 사이에서만 오가고 외부로 전송되지 않습니다."),
            ]),
            Section(title: String(localized: "4. 알림과 알람"), paragraphs: [
                String(localized: "운동 알림과 휴식 종료 알람은 iPhone 안에서 예약되고 울리며, 이 과정에서 외부로 보내는 정보는 없습니다. 알림은 설정에서 언제든 끌 수 있습니다."),
            ]),
            Section(title: String(localized: "5. 데이터 내보내기와 삭제"), paragraphs: [
                String(localized: "• 설정 → 데이터 관리에서 운동 기록을 백업 파일이나 CSV 파일로 내보낼 수 있습니다. 파일은 사용자가 직접 고른 곳으로만 공유됩니다."),
                String(localized: "• 같은 화면의 '모든 데이터 삭제'로 운동 기록, 신체 정보, 목표, 설정, 배지, 내 음식을 한 번에 지울 수 있고, 원하면 세트 카운터가 건강 앱에 저장한 기록도 함께 지울 수 있습니다."),
                String(localized: "• 앱을 삭제하면 앱 안의 데이터도 모두 삭제됩니다."),
                String(localized: "개발자는 사용자의 데이터를 갖고 있지 않으므로, 위 방법으로 지우면 남는 데이터가 없습니다."),
            ]),
            Section(title: String(localized: "6. 앱 내 구매 (세트 카운터 Pro)"), paragraphs: [
                String(localized: "세트 카운터 Pro 구독과 평생 이용권은 Apple의 App Store가 결제를 처리합니다. 앱과 개발자는 카드 번호 같은 결제 정보를 받지 않습니다. 앱은 Pro를 쓸 수 있는지 확인하려고 App Store가 기기에 보관하는 구매 기록을 기기 안에서만 확인하며, 이 정보를 외부로 보내지 않습니다."),
            ]),
            Section(title: String(localized: "7. 광고, 분석 도구, 쿠키"), paragraphs: [
                String(localized: "앱에는 광고, 분석 도구, 외부 SDK가 없고, 쿠키를 쓰지 않으며, 다른 앱이나 웹사이트에서 사용자를 추적하지 않습니다."),
            ]),
            Section(title: String(localized: "8. 문의 메일"), paragraphs: [
                String(localized: "앱의 \"지원 및 피드백\"에서 메일을 보내면 본문에 앱 버전, 기기 모델, iOS 버전이 자동으로 들어갑니다. 보내기 전에 확인하고 지울 수 있으며, 받은 메일은 답변에만 사용합니다. 앱은 광고나 홍보 메일을 보내지 않습니다."),
            ]),
            Section(title: String(localized: "9. 만 14세 미만 아동"), paragraphs: [
                String(localized: "이 앱은 만 14세 이상을 위한 앱이며, 나이는 14세부터 입력할 수 있습니다. 개발자는 아동을 포함해 누구의 개인정보도 수집하지 않습니다."),
            ]),
            Section(title: String(localized: "10. 방침 변경"), paragraphs: [
                String(localized: "이 방침이 바뀌면 앱과 웹 페이지에 새 시행일과 함께 게시합니다."),
            ]),
            Section(title: String(localized: "11. 연락처"), paragraphs: [AppInfo.supportEmail]),
        ]
    }

    private static var termsSections: [Section] {
        [
            Section(title: String(localized: "1. 적용"), paragraphs: [
                String(localized: "이 약관은 세트 카운터 앱(이하 \"앱\")을 이용할 때 적용됩니다. App Store에서 받은 앱에는 Apple의 표준 사용권 계약(EULA)도 함께 적용되며, 이 약관과 다른 부분은 EULA를 따릅니다."),
            ]),
            Section(title: String(localized: "2. 서비스"), paragraphs: [
                String(localized: "앱은 세트 카운트, 휴식 타이머, 운동·식단·체중 기록과 통계를 제공합니다. 운동을 기록하는 기능, 백업, 배지는 무료입니다. 자세한 통계, 지난 리포트, Apple Watch 앱, 루틴 편집, 일부 위젯과 테마는 세트 카운터 Pro(유료)에서 쓸 수 있으며, 앱 안에 'PRO' 표시와 자물쇠로 표시합니다."),
            ]),
            Section(title: String(localized: "3. Pro 결제와 자동 갱신"), paragraphs: [
                String(localized: "• 가격은 연간 ₩22,000(처음 7일 무료 체험), 월간 ₩2,900, 평생 ₩49,000이며, 실제 금액은 결제 화면에 표시되는 가격이 기준입니다. 숨겨진 추가 요금은 없습니다."),
                String(localized: "• 결제는 Apple 계정으로 이뤄집니다. 구독은 해지하지 않으면 기간이 끝날 때 같은 금액으로 자동 갱신됩니다."),
                String(localized: "• 무료 체험이나 구독은 끝나기 24시간 전까지 iPhone 설정 → Apple 계정 → 구독에서 해지하면 더 결제되지 않습니다. 해지해도 이미 결제한 기간이 끝날 때까지 Pro를 쓸 수 있습니다."),
                String(localized: "• 구독 가격이 바뀌면 Apple이 미리 알리며, 필요한 경우 사용자의 동의를 받습니다."),
                String(localized: "• 평생 이용권은 한 번 결제로 계속 쓸 수 있고, 같은 Apple 계정의 기기에서 '구매 복원'으로 다시 받을 수 있습니다."),
                String(localized: "• 환불은 환불 정책을 따릅니다."),
            ]),
            Section(title: String(localized: "4. 건강 정보 안내"), paragraphs: [
                String(localized: "앱이 보여주는 칼로리, 기초대사량, 심박수, 추천 무게·횟수는 공식과 기기 측정값으로 계산한 추정치이며, 의학적 진단이나 조언이 아닙니다. 운동 중 통증이나 어지러움이 있으면 바로 멈추고, 질환이 있거나 식단을 크게 바꾸려면 의사나 전문가와 상의하세요."),
            ]),
            Section(title: String(localized: "5. 데이터 보관"), paragraphs: [
                String(localized: "기록은 사용자의 iPhone에만 저장되고 개발자 서버에 백업되지 않습니다. 기기를 잃어버리거나 앱을 지우면 복구할 수 없으니, 설정 → 데이터 관리에서 백업 파일을 만들어 두세요."),
            ]),
            Section(title: String(localized: "6. 책임"), paragraphs: [
                String(localized: "개발자는 앱을 안정적으로 제공하려고 노력합니다. 다만 기기나 운영체제의 문제, 사용자의 설정, 추정치를 그대로 따라 생긴 결과에 대해서는 개발자의 고의나 중대한 과실이 없는 한 책임지지 않습니다."),
            ]),
            Section(title: String(localized: "7. 약관 변경"), paragraphs: [
                String(localized: "약관을 바꾸면 앱과 웹 페이지에 새 시행일과 함께 게시합니다."),
            ]),
            Section(title: String(localized: "8. 문의"), paragraphs: [AppInfo.supportEmail]),
        ]
    }

    private static var refundSections: [Section] {
        [
            Section(title: String(localized: "1. 결제와 환불은 Apple이 처리합니다"), paragraphs: [
                String(localized: "세트 카운터 Pro는 App Store를 통해 판매되며, 결제와 환불은 Apple의 정책을 따릅니다. 개발자는 결제 정보를 볼 수 없고 직접 환불해 드릴 수 없습니다."),
            ]),
            Section(title: String(localized: "2. 환불 요청 방법"), paragraphs: [
                String(localized: "• 앱의 설정 → 세트 카운터 Pro → '환불 요청'을 누르거나, reportaproblem.apple.com에서 신청할 수 있습니다."),
                String(localized: "• Apple이 요청을 검토해 환불 여부를 정하고, 결과를 Apple 계정 이메일로 알려 줍니다."),
            ]),
            Section(title: String(localized: "3. 무료 체험과 해지"), paragraphs: [
                String(localized: "• 7일 무료 체험이 끝나기 24시간 전까지 해지하면 결제되지 않습니다."),
                String(localized: "• 구독을 해지하면 다음 갱신부터 결제되지 않고, 이미 결제한 기간은 끝날 때까지 쓸 수 있습니다. 남은 기간에 대한 부분 환불은 Apple이 승인한 경우에만 이뤄집니다."),
            ]),
            Section(title: String(localized: "4. 환불된 뒤"), paragraphs: [
                String(localized: "환불되면 Pro 기능이 다시 잠기지만, 운동 기록과 데이터는 그대로 남습니다."),
            ]),
            Section(title: String(localized: "5. 결제했는데 Pro가 켜지지 않을 때"), paragraphs: [
                String(localized: "결제 화면의 '구매 복원'을 먼저 눌러 보시고, 그래도 안 되면 아래 이메일로 알려 주세요."),
                AppInfo.supportEmail,
            ]),
        ]
    }
}

/// One legal document, with links to the web copy or Apple where they matter.
struct LegalDocumentView: View {
    let document: LegalDocument

    @State private var requestingRefund = false
    private let store = ProStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("시행일 \(LegalDocument.effectiveDate.formatted(date: .long, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(document.summary)
                    .font(.subheadline.weight(.medium))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.headline)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .padding(.leading, paragraph.hasPrefix("• ") ? 4 : 0)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                links
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .refundRequestSheet(for: store.transactionID ?? 0, isPresented: $requestingRefund)
    }

    @ViewBuilder
    private var links: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch document {
            case .privacy:
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("웹에서 보기", systemImage: "safari")
                }
            case .terms:
                Link(destination: AppInfo.termsURL) {
                    Label("Apple 표준 사용권 계약(EULA)", systemImage: "doc.text")
                }
                NavigationLink {
                    LegalDocumentView(document: .refund)
                } label: {
                    Label("환불 정책", systemImage: LegalDocument.refund.systemImage)
                }
            case .refund:
                if store.transactionID != nil {
                    Button("환불 요청", systemImage: "arrow.uturn.backward") { requestingRefund = true }
                }
                Link(destination: AppInfo.reportProblemURL) {
                    Label("reportaproblem.apple.com", systemImage: "safari")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}
