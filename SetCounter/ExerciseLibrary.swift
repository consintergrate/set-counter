import Foundation

/// A built-in exercise with the muscle it trains and a light first weight (kg).
struct LibraryExercise: Hashable, Identifiable {
    let name: String
    let muscle: Muscle
    let startWeight: Double
    /// Part of the short starter list suggested routines draw from.
    var starter = false
    var id: String { name }
}

/// The exercise list behind the picker, the setup screen, and suggested routines.
enum ExerciseLibrary {
    static let all: [LibraryExercise] = [
        // Chest
        LibraryExercise(name: String(localized: "벤치프레스"), muscle: .chest, startWeight: 20, starter: true),
        LibraryExercise(name: String(localized: "인클라인 벤치프레스"), muscle: .chest, startWeight: 20),
        LibraryExercise(name: String(localized: "덤벨 벤치프레스"), muscle: .chest, startWeight: 10),
        LibraryExercise(name: String(localized: "인클라인 덤벨 프레스"), muscle: .chest, startWeight: 10, starter: true),
        LibraryExercise(name: String(localized: "체스트 프레스 머신"), muscle: .chest, startWeight: 20),
        LibraryExercise(name: String(localized: "케이블 플라이"), muscle: .chest, startWeight: 10, starter: true),
        LibraryExercise(name: String(localized: "펙덱 플라이"), muscle: .chest, startWeight: 20),
        LibraryExercise(name: String(localized: "푸시업"), muscle: .chest, startWeight: 0, starter: true),
        // Back
        LibraryExercise(name: String(localized: "풀업"), muscle: .back, startWeight: 0, starter: true),
        LibraryExercise(name: String(localized: "랫풀다운"), muscle: .back, startWeight: 30, starter: true),
        LibraryExercise(name: String(localized: "바벨 로우"), muscle: .back, startWeight: 30, starter: true),
        LibraryExercise(name: String(localized: "덤벨 로우"), muscle: .back, startWeight: 12),
        LibraryExercise(name: String(localized: "시티드 케이블 로우"), muscle: .back, startWeight: 30, starter: true),
        LibraryExercise(name: String(localized: "티바 로우"), muscle: .back, startWeight: 20),
        // Shoulders
        LibraryExercise(name: String(localized: "오버헤드 프레스"), muscle: .shoulders, startWeight: 20, starter: true),
        LibraryExercise(name: String(localized: "덤벨 숄더 프레스"), muscle: .shoulders, startWeight: 8),
        LibraryExercise(name: String(localized: "사이드 레터럴 레이즈"), muscle: .shoulders, startWeight: 5, starter: true),
        LibraryExercise(name: String(localized: "프론트 레이즈"), muscle: .shoulders, startWeight: 5),
        LibraryExercise(name: String(localized: "리어 델트 레이즈"), muscle: .shoulders, startWeight: 5, starter: true),
        LibraryExercise(name: String(localized: "페이스 풀"), muscle: .shoulders, startWeight: 10),
        // Biceps
        LibraryExercise(name: String(localized: "바벨 컬"), muscle: .biceps, startWeight: 15, starter: true),
        LibraryExercise(name: String(localized: "덤벨 컬"), muscle: .biceps, startWeight: 6),
        LibraryExercise(name: String(localized: "해머 컬"), muscle: .biceps, startWeight: 8, starter: true),
        LibraryExercise(name: String(localized: "프리처 컬"), muscle: .biceps, startWeight: 10),
        LibraryExercise(name: String(localized: "케이블 컬"), muscle: .biceps, startWeight: 10),
        // Triceps
        LibraryExercise(name: String(localized: "케이블 푸시다운"), muscle: .triceps, startWeight: 15, starter: true),
        LibraryExercise(name: String(localized: "라잉 트라이셉 익스텐션"), muscle: .triceps, startWeight: 15, starter: true),
        LibraryExercise(name: String(localized: "오버헤드 트라이셉 익스텐션"), muscle: .triceps, startWeight: 10),
        LibraryExercise(name: String(localized: "덤벨 킥백"), muscle: .triceps, startWeight: 5),
        LibraryExercise(name: String(localized: "딥스"), muscle: .triceps, startWeight: 0),
        LibraryExercise(name: String(localized: "클로즈그립 벤치프레스"), muscle: .triceps, startWeight: 20),
        // Legs
        LibraryExercise(name: String(localized: "스쿼트"), muscle: .legs, startWeight: 30, starter: true),
        LibraryExercise(name: String(localized: "데드리프트"), muscle: .legs, startWeight: 40),
        LibraryExercise(name: String(localized: "레그 프레스"), muscle: .legs, startWeight: 60, starter: true),
        LibraryExercise(name: String(localized: "루마니안 데드리프트"), muscle: .legs, startWeight: 30, starter: true),
        LibraryExercise(name: String(localized: "런지"), muscle: .legs, startWeight: 10),
        LibraryExercise(name: String(localized: "불가리안 스플릿 스쿼트"), muscle: .legs, startWeight: 8),
        LibraryExercise(name: String(localized: "레그 익스텐션"), muscle: .legs, startWeight: 20),
        LibraryExercise(name: String(localized: "레그 컬"), muscle: .legs, startWeight: 20, starter: true),
        LibraryExercise(name: String(localized: "힙 쓰러스트"), muscle: .legs, startWeight: 30),
        LibraryExercise(name: String(localized: "카프 레이즈"), muscle: .legs, startWeight: 30, starter: true),
        // Core
        LibraryExercise(name: String(localized: "크런치"), muscle: .core, startWeight: 0, starter: true),
        LibraryExercise(name: String(localized: "케이블 크런치"), muscle: .core, startWeight: 20, starter: true),
        LibraryExercise(name: String(localized: "리버스 크런치"), muscle: .core, startWeight: 0, starter: true),
        LibraryExercise(name: String(localized: "행잉 레그 레이즈"), muscle: .core, startWeight: 0),
        LibraryExercise(name: String(localized: "러시안 트위스트"), muscle: .core, startWeight: 0),
        LibraryExercise(name: String(localized: "AB 롤아웃"), muscle: .core, startWeight: 0),
    ]

    static func exercises(for muscle: Muscle) -> [LibraryExercise] {
        all.filter { $0.muscle == muscle }
    }

    /// Matches "덤벨프레스" to "덤벨 프레스": spacing, hyphens, and case are ignored.
    static func normalized(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func find(_ name: String) -> LibraryExercise? {
        let key = normalized(name)
        return all.first { normalized($0.name) == key }
    }
}
