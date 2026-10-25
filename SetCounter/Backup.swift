import Foundation
import SwiftData

/// Everything needed to move the app to another iPhone or back after a reinstall.
struct BackupFile: Codable {
    struct Record: Codable {
        var date: Date
        var exercise: String
        var routineName: String
        var routineIndex: Int
        var duration: TimeInterval
        var calories: Double
        var averageHeartRate: Int
        var maxHeartRate: Int
        var sets: [SetValue]
    }

    struct Exercise: Codable {
        var name: String
        var muscle: String
    }

    /// One UserDefaults value with its type, so it comes back as the same type.
    struct Setting: Codable {
        var key: String
        var kind: String
        var value: String
    }

    var app = "SetCounter"
    var version = 1
    var exportedAt: Date
    var records: [Record]
    var exercises: [Exercise]
    var settings: [Setting]
}

enum BackupError: LocalizedError {
    case notABackup, unreadableCSV

    var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "세트 카운터 백업 파일이 아니에요.")
        case .unreadableCSV: String(localized: "CSV에서 날짜와 운동 이름 열을 찾지 못했어요.")
        }
    }
}

enum Backup {
    /// Settings carried in a backup. Language and permission-dependent state stay per device.
    static let settingKeys = [
        "exercise", "weight", "reps", "totalSets", "restSeconds", WeightUnit.key, Routine.namesKey, "weeklyGoal",
        "notifyTime", "notifyWeekdays", "theme", "accent", "keepScreenOn", "showMetrics", "showElapsed", "hapticsOn",
        "alarmVolume", "vibrationOn", AlarmSound.key, "alarmDuration", "bodyWeight", "age", "isMale", "useHealthKit",
    ]

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Export

    static func make(records: [WorkoutRecord], profiles: [ExerciseProfile], now: Date = Date()) -> BackupFile {
        BackupFile(
            exportedAt: now,
            records: records.map {
                BackupFile.Record(date: $0.date, exercise: $0.exercise, routineName: $0.routineName, routineIndex: $0.routineIndex,
                                  duration: $0.duration, calories: $0.calories, averageHeartRate: $0.averageHeartRate,
                                  maxHeartRate: $0.maxHeartRate, sets: $0.setValues)
            },
            exercises: profiles.map { BackupFile.Exercise(name: $0.name, muscle: $0.muscleRaw) },
            settings: settingKeys.compactMap(setting(for:))
        )
    }

    /// Writes the backup to a protected temporary file for the share sheet.
    static func write(records: [WorkoutRecord], profiles: [ExerciseProfile]) throws -> URL {
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SetCounter-backup-\(day).json")
        try encoder.encode(make(records: records, profiles: profiles)).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func removeExports() {
        let folder = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasPrefix("SetCounter-backup-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private static func setting(for key: String) -> BackupFile.Setting? {
        guard let object = UserDefaults.standard.object(forKey: key) else { return nil }
        switch object {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return .init(key: key, kind: "bool", value: number.boolValue ? "1" : "0")
        case let number as NSNumber where CFNumberIsFloatType(number):
            return .init(key: key, kind: "double", value: String(number.doubleValue))
        case let number as NSNumber:
            return .init(key: key, kind: "int", value: String(number.intValue))
        case let text as String:
            return .init(key: key, kind: "string", value: text)
        default:
            return nil
        }
    }

    // MARK: Import

    static func read(_ data: Data) throws -> BackupFile {
        guard let file = try? decoder.decode(BackupFile.self, from: data), file.app == "SetCounter" else {
            throw BackupError.notABackup
        }
        return file
    }

    /// Adds the backup's records. With `replacing`, existing records are deleted first
    /// and settings are restored too; otherwise records already present are skipped.
    /// Returns how many records were added.
    @discardableResult
    static func restore(_ file: BackupFile, replacing: Bool, into context: ModelContext) throws -> Int {
        if replacing {
            try context.delete(model: WorkoutRecord.self)
            try context.delete(model: SetEntry.self)
            for setting in file.settings where settingKeys.contains(setting.key) { apply(setting) }
        }
        let added = insert(file.records, into: context, skippingExisting: !replacing)

        let existing = try context.fetch(FetchDescriptor<ExerciseProfile>())
        for exercise in file.exercises {
            if let profile = existing.first(where: { $0.name == exercise.name }) {
                if replacing { profile.muscleRaw = exercise.muscle }
            } else {
                context.insert(ExerciseProfile(name: exercise.name, muscle: Muscle(rawValue: exercise.muscle) ?? .other))
            }
        }
        try context.save()
        return added
    }

    static func insert(_ records: [BackupFile.Record], into context: ModelContext, skippingExisting: Bool) -> Int {
        var known = Set<String>()
        if skippingExisting, let current = try? context.fetch(FetchDescriptor<WorkoutRecord>()) {
            known = Set(current.map { key($0.exercise, $0.date) })
        }
        var added = 0
        for item in records where !item.sets.isEmpty {
            guard known.insert(key(item.exercise, item.date)).inserted else { continue }
            let record = WorkoutRecord(date: item.date, exercise: item.exercise, sets: 0, weight: 0, reps: 0, duration: item.duration,
                                       calories: item.calories, averageHeartRate: item.averageHeartRate, maxHeartRate: item.maxHeartRate,
                                       routineIndex: item.routineIndex, routineName: item.routineName)
            context.insert(record)
            record.replaceSets(item.sets, in: context)
            added += 1
        }
        return added
    }

    /// Same exercise started in the same second counts as the same record.
    private static func key(_ exercise: String, _ date: Date) -> String {
        "\(exercise)|\(Int(date.timeIntervalSince1970))"
    }

    private static func apply(_ setting: BackupFile.Setting) {
        let defaults = UserDefaults.standard
        switch setting.kind {
        case "bool": defaults.set(setting.value == "1", forKey: setting.key)
        case "int": if let value = Int(setting.value) { defaults.set(value, forKey: setting.key) }
        case "double": if let value = Double(setting.value) { defaults.set(value, forKey: setting.key) }
        default: defaults.set(setting.value, forKey: setting.key)
        }
    }
}
