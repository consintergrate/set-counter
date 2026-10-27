import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    private enum ImportKind { case backup, csv }

    @State private var confirmingDelete = false
    @State private var csvURL: URL?
    @State private var backupURL: URL?
    @State private var importKind: ImportKind?
    @State private var pendingBackup: BackupFile?
    @State private var resultMessage: String?

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
                if ProStore.shared.isPro {
                    NavigationLink {
                        ExerciseNamesView()
                    } label: {
                        Label("운동 이름 관리", systemImage: "character.cursor.ibeam")
                    }
                } else {
                    ProLockedButton(title: "운동 이름 관리", systemImage: "character.cursor.ibeam", feature: .data)
                }
            }

            Section {
                exportRow("백업 파일 만들기", systemImage: "externaldrive.badge.plus", url: backupURL)
                Button("백업에서 복원", systemImage: "externaldrive.badge.checkmark") { importKind = .backup }
            } header: {
                Text("백업")
            } footer: {
                Text("기록, 세트별 무게·횟수, 운동 부위, 앱 설정이 파일 하나에 담겨요. 파일 앱이나 iCloud Drive에 저장해두면 새 iPhone이나 재설치 후에 복원할 수 있어요.")
            }

            Section {
                if ProStore.shared.isPro {
                    exportRow("CSV로 내보내기", systemImage: "square.and.arrow.up", url: csvURL)
                    Button("CSV 가져오기", systemImage: "square.and.arrow.down") { importKind = .csv }
                } else {
                    ProLockedButton(title: "CSV로 내보내기", systemImage: "square.and.arrow.up", feature: .data)
                    ProLockedButton(title: "CSV 가져오기", systemImage: "square.and.arrow.down", feature: .data)
                }
                Button("건강 앱에서 운동 보기", systemImage: "heart.text.square") {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                }
            } header: {
                Text("CSV")
            } footer: {
                Text("CSV 파일은 엑셀·Numbers·구글 시트에서 열 수 있어요. 이 앱에서 내보낸 CSV를 가져오면 이미 있는 기록은 건너뛰어요.")
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
            csvURL = try? CSVExporter.write(records)
            backupURL = try? Backup.write(records: records, profiles: profiles)
        }
        .onDisappear {
            CSVExporter.removeExport()
            Backup.removeExports()
        }
        .fileImporter(
            isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
            allowedContentTypes: importKind == .csv ? [.commaSeparatedText, .plainText] : [.json]
        ) { result in
            let kind = importKind
            importKind = nil
            handleImport(result, kind: kind)
        }
        .confirmationDialog(
            "백업을 어떻게 복원할까요?",
            isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
            titleVisibility: .visible
        ) {
            Button("지금 기록에 합치기") { restorePending(replacing: false) }
            Button("모두 백업으로 바꾸기", role: .destructive) { restorePending(replacing: true) }
        } message: {
            if let pendingBackup {
                Text("백업에 기록 \(pendingBackup.records.count)개가 있어요. 바꾸기를 고르면 지금 기록을 지우고 설정도 백업대로 돌려요.")
            }
        }
        .alert("데이터", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
        .confirmationDialog("모든 운동 기록을 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("\(records.count)개 기록 삭제", role: .destructive) {
                // Batch deletes skip the cascade rule, so per-set rows go explicitly.
                try? modelContext.delete(model: WorkoutRecord.self)
                try? modelContext.delete(model: SetEntry.self)
            }
        } message: {
            Text("삭제한 기록은 되돌릴 수 없어요. 먼저 백업 파일을 만들어두는 걸 추천해요.")
        }
    }

    @ViewBuilder
    private func exportRow(_ title: LocalizedStringKey, systemImage: String, url: URL?) -> some View {
        if let url {
            ShareLink(item: url) { Label(title, systemImage: systemImage) }
        } else {
            Label(title, systemImage: systemImage).foregroundStyle(.secondary)
        }
    }

    private func handleImport(_ result: Result<URL, any Error>, kind: ImportKind?) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            switch kind {
            case .backup:
                pendingBackup = try Backup.read(data)
            case .csv:
                let rows = try CSVImporter.records(from: data)
                let added = Backup.insert(rows, into: modelContext, skippingExisting: true)
                try modelContext.save()
                resultMessage = String(localized: "기록 \(added)개를 가져왔어요. 이미 있던 \(rows.count - added)개는 건너뛰었어요.")
            case nil:
                break
            }
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func restorePending(replacing: Bool) {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        do {
            let added = try Backup.restore(backup, replacing: replacing, into: modelContext)
            BadgeCenter.shared.reload()
            resultMessage = String(localized: "기록 \(added)개를 복원했어요.")
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

enum CSVExporter {
    static let header = "date,routine,exercise,weight_kg,reps,sets,volume_kg,duration_sec,calories_kcal,avg_hr,max_hr,sets_detail"

    /// Writes all records to a CSV in the temporary directory. Weights are in kg;
    /// `sets_detail` lists every set as weight x reps, separated by `|`.
    static func write(_ records: [WorkoutRecord]) throws -> URL {
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
                r.setValues.map { "\($0.weight)x\($0.reps)" }.joined(separator: "|"),
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

    /// Starts that a spreadsheet would run as a formula ("=HYPERLINK(…)").
    static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func escape(_ value: String) -> String {
        // A leading apostrophe makes Excel and Numbers show the text as is; the
        // importer strips it again.
        var value = value
        if let first = value.first, formulaStarts.contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Reads CSVs in the export format above. Older exports without `sets_detail`
/// fall back to weight × reps × sets.
enum CSVImporter {
    static func records(from data: Data) throws -> [BackupFile.Record] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = parse(text)
        guard let header = rows.first,
              let dateColumn = header.firstIndex(of: "date"),
              let exerciseColumn = header.firstIndex(of: "exercise") else { throw BackupError.unreadableCSV }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let iso = ISO8601DateFormatter()

        return rows.dropFirst().compactMap { row in
            func field(_ index: Int?) -> String? {
                guard let index, row.indices.contains(index) else { return nil }
                let value = row[index]
                // Undo the export's formula guard ("'=…" back to "=…").
                if value.hasPrefix("'"), let next = value.dropFirst().first, CSVExporter.formulaStarts.contains(next) {
                    return String(value.dropFirst())
                }
                return value
            }
            guard let date = field(dateColumn).flatMap(iso.date(from:)),
                  let exercise = field(exerciseColumn), !exercise.isEmpty else { return nil }
            var sets = (field(column("sets_detail")) ?? "")
                .split(separator: "|")
                .compactMap { part -> SetValue? in
                    let pieces = part.split(separator: "x")
                    guard pieces.count == 2, let weight = Double(pieces[0]), let reps = Int(pieces[1]) else { return nil }
                    return SetValue(weight: weight, reps: reps)
                }
            if sets.isEmpty,
               let weight = field(column("weight_kg")).flatMap(Double.init),
               let reps = field(column("reps")).flatMap(Int.init),
               let count = field(column("sets")).flatMap(Int.init), count > 0 {
                sets = Array(repeating: SetValue(weight: weight, reps: reps), count: count)
            }
            return BackupFile.Record(
                date: date,
                exercise: exercise,
                routineName: field(column("routine")) ?? "",
                routineIndex: -1,
                duration: field(column("duration_sec")).flatMap(Double.init) ?? 0,
                calories: field(column("calories_kcal")).flatMap(Double.init) ?? 0,
                averageHeartRate: field(column("avg_hr")).flatMap(Int.init) ?? 0,
                maxHeartRate: field(column("max_hr")).flatMap(Int.init) ?? 0,
                sets: sets
            )
        }
    }

    /// Minimal RFC 4180 parser: quoted fields, doubled quotes, CRLF or LF.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(char)
            }
        }
        row.append(field)
        if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        return rows
    }
}
