import SwiftUI

/// A food with rough calories for one serving. The name includes the serving
/// ("김밥 1줄") so it reads naturally in the meal log.
struct FoodItem: Codable, Hashable, Identifiable {
    var name: String
    var kcal: Int
    var id: String { name }
}

enum FoodCategory: String, CaseIterable, Identifiable {
    case recent, mine, rice, korean, protein, quick, snack, fruit, drink
    var id: Self { self }

    var title: String {
        switch self {
        case .recent: String(localized: "최근")
        case .mine: String(localized: "내 음식")
        case .rice: String(localized: "밥·면")
        case .korean: String(localized: "한식")
        case .protein: String(localized: "단백질")
        case .quick: String(localized: "간편식·외식")
        case .snack: String(localized: "빵·간식")
        case .fruit: String(localized: "과일")
        case .drink: String(localized: "음료·술")
        }
    }
}

/// Built-in foods with typical calories, plus the user's own foods and recent picks.
enum FoodCatalog {
    static let builtIn: [FoodCategory: [FoodItem]] = [
        .rice: [
            FoodItem(name: String(localized: "공깃밥 1공기"), kcal: 300),
            FoodItem(name: String(localized: "현미밥 1공기"), kcal: 290),
            FoodItem(name: String(localized: "김밥 1줄"), kcal: 450),
            FoodItem(name: String(localized: "참치김밥 1줄"), kcal: 520),
            FoodItem(name: String(localized: "비빔밥 1그릇"), kcal: 600),
            FoodItem(name: String(localized: "볶음밥 1인분"), kcal: 650),
            FoodItem(name: String(localized: "제육덮밥 1그릇"), kcal: 750),
            FoodItem(name: String(localized: "라면 1개"), kcal: 500),
            FoodItem(name: String(localized: "짜장면 1그릇"), kcal: 700),
            FoodItem(name: String(localized: "짬뽕 1그릇"), kcal: 690),
            FoodItem(name: String(localized: "칼국수 1그릇"), kcal: 600),
            FoodItem(name: String(localized: "냉면 1그릇"), kcal: 550),
            FoodItem(name: String(localized: "우동 1그릇"), kcal: 450),
            FoodItem(name: String(localized: "쌀국수 1그릇"), kcal: 450),
            FoodItem(name: String(localized: "파스타 1접시"), kcal: 650),
        ],
        .korean: [
            FoodItem(name: String(localized: "김치찌개 1인분"), kcal: 250),
            FoodItem(name: String(localized: "된장찌개 1인분"), kcal: 200),
            FoodItem(name: String(localized: "순두부찌개 1인분"), kcal: 300),
            FoodItem(name: String(localized: "미역국 1그릇"), kcal: 120),
            FoodItem(name: String(localized: "제육볶음 1인분"), kcal: 450),
            FoodItem(name: String(localized: "불고기 1인분"), kcal: 400),
            FoodItem(name: String(localized: "삼겹살 1인분 (200g)"), kcal: 660),
            FoodItem(name: String(localized: "닭갈비 1인분"), kcal: 500),
            FoodItem(name: String(localized: "떡볶이 1인분"), kcal: 480),
            FoodItem(name: String(localized: "순대 1인분"), kcal: 380),
            FoodItem(name: String(localized: "계란말이 1접시"), kcal: 200),
            FoodItem(name: String(localized: "김치 1접시"), kcal: 20),
        ],
        .protein: [
            FoodItem(name: String(localized: "닭가슴살 1팩 (100g)"), kcal: 120),
            FoodItem(name: String(localized: "계란 1개"), kcal: 75),
            FoodItem(name: String(localized: "프로틴 쉐이크 1잔"), kcal: 130),
            FoodItem(name: String(localized: "그릭요거트 1컵"), kcal: 120),
            FoodItem(name: String(localized: "두부 반 모"), kcal: 150),
            FoodItem(name: String(localized: "참치캔 1캔"), kcal: 180),
            FoodItem(name: String(localized: "연어 100g"), kcal: 200),
            FoodItem(name: String(localized: "소고기 스테이크 200g"), kcal: 500),
            FoodItem(name: String(localized: "고구마 1개"), kcal: 160),
            FoodItem(name: String(localized: "감자 1개"), kcal: 130),
        ],
        .quick: [
            FoodItem(name: String(localized: "편의점 도시락"), kcal: 750),
            FoodItem(name: String(localized: "삼각김밥 1개"), kcal: 200),
            FoodItem(name: String(localized: "샌드위치 1개"), kcal: 350),
            FoodItem(name: String(localized: "컵라면 (소)"), kcal: 300),
            FoodItem(name: String(localized: "햄버거 1개"), kcal: 550),
            FoodItem(name: String(localized: "감자튀김 (M)"), kcal: 350),
            FoodItem(name: String(localized: "피자 1조각"), kcal: 280),
            FoodItem(name: String(localized: "치킨 1조각"), kcal: 250),
            FoodItem(name: String(localized: "만두 5개"), kcal: 300),
            FoodItem(name: String(localized: "핫도그 1개"), kcal: 300),
        ],
        .snack: [
            FoodItem(name: String(localized: "식빵 1장"), kcal: 100),
            FoodItem(name: String(localized: "베이글 1개"), kcal: 270),
            FoodItem(name: String(localized: "크로와상 1개"), kcal: 230),
            FoodItem(name: String(localized: "떡 100g"), kcal: 220),
            FoodItem(name: String(localized: "견과류 1줌"), kcal: 170),
            FoodItem(name: String(localized: "초코바 1개"), kcal: 230),
            FoodItem(name: String(localized: "과자 1봉 (소)"), kcal: 250),
            FoodItem(name: String(localized: "아이스크림 1개"), kcal: 200),
            FoodItem(name: String(localized: "케이크 1조각"), kcal: 350),
        ],
        .fruit: [
            FoodItem(name: String(localized: "바나나 1개"), kcal: 90),
            FoodItem(name: String(localized: "사과 1개"), kcal: 100),
            FoodItem(name: String(localized: "귤 1개"), kcal: 40),
            FoodItem(name: String(localized: "딸기 10개"), kcal: 50),
            FoodItem(name: String(localized: "포도 반 송이"), kcal: 100),
            FoodItem(name: String(localized: "수박 1조각"), kcal: 80),
            FoodItem(name: String(localized: "블루베리 1컵"), kcal: 85),
        ],
        .drink: [
            FoodItem(name: String(localized: "아메리카노"), kcal: 10),
            FoodItem(name: String(localized: "카페라떼"), kcal: 180),
            FoodItem(name: String(localized: "바닐라라떼"), kcal: 250),
            FoodItem(name: String(localized: "우유 1잔"), kcal: 130),
            FoodItem(name: String(localized: "두유 1팩"), kcal: 130),
            FoodItem(name: String(localized: "오렌지주스 1잔"), kcal: 110),
            FoodItem(name: String(localized: "콜라 1캔"), kcal: 140),
            FoodItem(name: String(localized: "제로 탄산음료"), kcal: 0),
            FoodItem(name: String(localized: "맥주 1캔 (355ml)"), kcal: 150),
            FoodItem(name: String(localized: "소주 1병"), kcal: 400),
            FoodItem(name: String(localized: "막걸리 1병"), kcal: 370),
            FoodItem(name: String(localized: "와인 1잔"), kcal: 120),
        ],
    ]

    static var all: [FoodItem] { FoodCategory.allCases.flatMap { builtIn[$0] ?? [] } }

    // MARK: The user's own foods and recent picks

    static let customKey = "customFoods"
    static let recentKey = "recentFoods"

    static var custom: [FoodItem] { load(customKey) }
    static var recent: [FoodItem] { load(recentKey) }

    /// Remembers a typed-in food so it shows under 내 음식 next time.
    static func addCustom(_ item: FoodItem) {
        var items = custom.filter { $0.name != item.name }
        items.insert(item, at: 0)
        store(Array(items.prefix(50)), key: customKey)
    }

    static func removeCustom(_ item: FoodItem) {
        store(custom.filter { $0.name != item.name }, key: customKey)
    }

    /// Most recent first, at most 15.
    static func noteEaten(_ items: [FoodItem]) {
        let names = Set(items.map(\.name))
        store(Array((items + recent.filter { !names.contains($0.name) }).prefix(15)), key: recentKey)
    }

    static func items(in category: FoodCategory) -> [FoodItem] {
        switch category {
        case .recent: recent
        case .mine: custom
        default: builtIn[category] ?? []
        }
    }

    private static func load(_ key: String) -> [FoodItem] {
        guard let data = UserDefaults.standard.string(forKey: key)?.data(using: .utf8),
              let items = try? JSONDecoder().decode([FoodItem].self, from: data) else { return [] }
        return items
    }

    private static func store(_ items: [FoodItem], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
}

/// Which meal of the day; picked from the time by default.
enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner, snack
    var id: Self { self }

    var title: String {
        switch self {
        case .breakfast: String(localized: "아침")
        case .lunch: String(localized: "점심")
        case .dinner: String(localized: "저녁")
        case .snack: String(localized: "간식")
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: .yellow
        case .dinner: .indigo
        case .snack: .brown
        }
    }

    static func guess(at date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}
