import SwiftData
import SwiftUI

struct DataManagementView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var confirmingDelete = false
    @State private var exportURL: URL?

    private var workoutDays: Int {
        Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        Form {
            Section("저장된 데이터") {
                LabeledContent("운동 기록", value: String(localized: "\(records.count)개"))
                LabeledContent("운동한 날", value: String(localized: "\(workoutDays)일"))
                if let first = records.last {
                    LabeledContent("첫 기록", value: first.date.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("CSV로 내보내기", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("CSV로 내보내기", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
                Button("건강 앱에서 운동 보기", systemImage: "heart.text.square") {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                }
            } footer: {
                Text("CSV 파일은 엑셀·Numbers·구글 시트에서 열 수 있어요.")
            }

            Section {
                Button("모든 기록 삭제", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(records.isEmpty)
            } footer: {
                Text("앱 안의 운동 기록만 지워져요. 건강 앱에 저장된 운동은 그대로 남아요.")
            }
        }
        .navigationTitle("데이터 관리")
        .task(id: records.count) {
            exportURL = try? CSVExporter.write(records)
        }
        .onDisappear { CSVExporter.removeExport() }
        .confirmationDialog("모든 운동 기록을 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("\(records.count)개 기록 삭제", role: .destructive) {
                try? modelContext.delete(model: WorkoutRecord.self)
            }
        } message: {
            Text("삭제한 기록은 되돌릴 수 없어요.")
        }
    }
}

enum CSVExporter {
    /// Writes all records to a CSV in the temporary directory. Weights are in kg.
    static func write(_ records: [WorkoutRecord]) throws -> URL {
        let header = "date,routine,exercise,weight_kg,reps,sets,volume_kg,duration_sec,calories_kcal,avg_hr,max_hr"
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let rows = records.map { r in
            [
                formatter.string(from: r.date),
                escape(r.routineName),
                escape(r.exercise),
                String(r.weight),
                String(r.reps),
                String(r.sets),
                String(r.volume),
                String(Int(r.duration)),
                String(Int(r.calories)),
                String(r.averageHeartRate),
                String(r.maxHeartRate),
            ].joined(separator: ",")
        }
        let csv = ([header] + rows).joined(separator: "\n")
        let url = fileURL
        // BOM so Excel opens Korean text as UTF-8. The file holds heart rate data, so it's
        // encrypted while the phone is locked and removed when the screen goes away.
        try Data(("\u{FEFF}" + csv).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func removeExport() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SetCounter-workouts.csv")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
