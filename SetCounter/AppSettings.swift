import SwiftUI

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb

    var id: String { rawValue }

    static let key = "weightUnit"
    static var current: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .kg
    }

    private static let poundsPerKilogram = 2.20462

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * Self.poundsPerKilogram }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / Self.poundsPerKilogram }

    /// Plate step for lifts.
    var step: Double { self == .kg ? 2.5 : 5 }
    var symbol: String { rawValue }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "시스템 설정"
        case .light: "라이트"
        case .dark: "다크"
        }
    }

    /// Light and dark are Pro; without it the app follows the system.
    @MainActor
    static func effective(_ raw: String) -> ThemeChoice {
        ProStore.shared.isPro ? ThemeChoice(rawValue: raw) ?? .system : .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, orange, green, purple, pink, red

    var id: String { rawValue }

    /// Accent colors are Pro; without it the app stays blue.
    @MainActor
    static func effective(_ raw: String) -> AccentChoice {
        ProStore.shared.isPro ? AccentChoice(rawValue: raw) ?? .blue : .blue
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .orange: .orange
        case .green: .green
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .blue: "파랑"
        case .orange: "주황"
        case .green: "초록"
        case .purple: "보라"
        case .pink: "분홍"
        case .red: "빨강"
        }
    }
}

enum AlarmSound: String, CaseIterable, Identifiable {
    case beeps, bell, soft

    var id: String { rawValue }

    static let key = "alarmSound"
    static var current: AlarmSound {
        AlarmSound(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .beeps
    }

    var title: LocalizedStringKey {
        switch self {
        case .beeps: "삐삐삐"
        case .bell: "벨"
        case .soft: "부드러운 알림"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ko, en

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "시스템 설정"
        case .ko: "한국어"
        case .en: "English"
        }
    }

    static let key = "appLanguage"

    /// Takes effect on the next launch, through the standard AppleLanguages override.
    func apply() {
        let defaults = UserDefaults.standard
        defaults.set(rawValue, forKey: Self.key)
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    /// Address that feedback and support emails go to.
    static let supportEmail = "andykim0706@naver.com"

    /// Public privacy policy page, also entered in App Store Connect.
    static let privacyPolicyURL = URL(string: "https://claude.ai/artifact/VDeB6HUQK9HHy9namQKzAQ")!

    /// Apple's standard license agreement, which covers the Pro subscriptions.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Numeric App Store ID (from App Store Connect, after the app record is created).
    /// Until it's set, "앱 리뷰 남기기" falls back to the system review prompt.
    static let appStoreID: String? = nil

    static var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    static let changelog: [(version: String, notes: [LocalizedStringKey])] = [
        ("1.0", [
            "세트 카운터와 휴식 타이머",
            "운동 기록, 캘린더, 통계",
            "심박수 연결과 칼로리 계산",
            "분할 루틴, 주간 목표, 운동 알림",
            "홈 화면 위젯",
        ]),
    ]
}
