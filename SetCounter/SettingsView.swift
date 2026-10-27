import StoreKit
import SwiftData
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("notifyOn") private var notifyOn = false
    @AppStorage(RoutineNotifications.weeklyReportKey) private var weeklyReportOn = true
    @AppStorage(RoutineNotifications.dailyReportKey) private var dailyReportOn = false
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @AppStorage("notifyTime") private var notifyTime = RoutineNotifications.defaultTime
    @AppStorage("notifyWeekdays") private var notifyWeekdaysRaw = RoutineNotifications.defaultWeekdaysRaw
    @AppStorage("theme") private var theme = ThemeChoice.system.rawValue
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @State private var notificationsDenied = false
    @State private var showingGuide = false

    /// Everything reminders and the widget depend on that can change from these screens.
    private var scheduleKey: String {
        "\(routineRaw)|\(weeklyGoal)|\(notifyOn)|\(notifyTime)|\(notifyWeekdaysRaw)|\(unitRaw)|\(weeklyReportOn)|\(dailyReportOn)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ProPaywallView(isSheet: false)
                    } label: {
                        ProSettingsLabel()
                    }
                }

                Section {
                    NavigationLink {
                        WorkoutManagementView()
                    } label: {
                        SettingsLabel("운동 관리", systemImage: "dumbbell.fill", color: .blue)
                    }
                    NavigationLink {
                        WidgetSettingsView()
                    } label: {
                        SettingsLabel("위젯", systemImage: "square.grid.2x2.fill", color: .indigo)
                    }
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        SettingsLabel("언어", systemImage: "globe", color: .teal, value: (AppLanguage(rawValue: language) ?? .system).title)
                    }
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        SettingsLabel("테마", systemImage: "paintpalette.fill", color: .purple, value: ThemeChoice.effective(theme).title)
                    }
                }

                Section {
                    NavigationLink {
                        HeartRateSettingsView()
                    } label: {
                        SettingsLabel("심박수 (블루투스 연결)", systemImage: "heart.fill", color: .red)
                    }
                    Picker(selection: $unitRaw) {
                        ForEach(WeightUnit.allCases) { Text($0.symbol).tag($0.rawValue) }
                    } label: {
                        SettingsLabel("무게 단위", systemImage: "scalemass.fill", color: .brown)
                    }
                    NavigationLink {
                        DisplaySettingsView()
                    } label: {
                        SettingsLabel("표시", systemImage: "textformat.size", color: .gray)
                    }
                    NavigationLink {
                        RestAlarmSettingsView()
                    } label: {
                        SettingsLabel("휴식 알림 (알림음·진동)", systemImage: "bell.badge.fill", color: .orange)
                    }
                }

                Section {
                    Toggle(isOn: $notifyOn) {
                        SettingsLabel("운동 알림 받기", systemImage: "bell.fill", color: .pink)
                    }
                    if notifyOn {
                        NavigationLink("알림 시간 · 요일") { NotificationSettingsView() }
                    }
                    Toggle(isOn: $dailyReportOn) {
                        SettingsLabel("하루 리포트 알림 (저녁 9시)", systemImage: "doc.text.fill", color: .teal)
                    }
                    Toggle(isOn: $weeklyReportOn) {
                        SettingsLabel("주간 리포트 알림", systemImage: "chart.bar.doc.horizontal.fill", color: .mint)
                    }
                } footer: {
                    if notificationsDenied {
                        Text("알림 권한이 꺼져 있어요. 설정 앱 → 세트 카운터 → 알림에서 켜주세요.")
                            .foregroundStyle(.red)
                    } else {
                        Text("운동하는 날 아침에 \"오늘은 OO 하는 날이에요\" 알림을, 한 주의 마지막 날 저녁 8시에 주간 리포트를 보내드려요.")
                    }
                }

                Section {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        SettingsLabel("데이터 관리", systemImage: "externaldrive.fill", color: .green)
                    }
                    Button {
                        showingGuide = true
                    } label: {
                        SettingsLabel("사용법", systemImage: "questionmark.circle.fill", color: .orange)
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        SupportView()
                    } label: {
                        SettingsLabel("지원 및 피드백", systemImage: "envelope.fill", color: .cyan)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsLabel("정보", systemImage: "info.circle.fill", color: .gray, value: "v\(AppInfo.version)")
                    }
                }
            }
            .navigationTitle("설정")
        }
        .sheet(isPresented: $showingGuide) {
            OnboardingView { showingGuide = false }
        }
        .onChange(of: notifyOn) { _, isOn in
            guard isOn else { return }
            Task {
                let granted = await RoutineNotifications.requestAuthorization()
                notificationsDenied = !granted
                if !granted { notifyOn = false }
            }
        }
        .onChange(of: dailyReportOn) { _, isOn in
            guard isOn else { return }
            Task {
                let granted = await RoutineNotifications.requestAuthorization()
                notificationsDenied = !granted
                if !granted { dailyReportOn = false }
            }
        }
        .onChange(of: weeklyReportOn) { _, isOn in
            guard isOn else { return }
            Task {
                let granted = await RoutineNotifications.requestAuthorization()
                notificationsDenied = !granted
                if !granted { weeklyReportOn = false }
            }
        }
        .task(id: scheduleKey) {
            await RoutineNotifications.reschedule(records: records)
            WidgetSnapshot.write(records: records)
        }
    }
}

/// Settings-app style row: a white glyph on a colored rounded square.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    var value: LocalizedStringKey?

    init(_ title: LocalizedStringKey, systemImage: String, color: Color, value: LocalizedStringKey? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            Text(title)
            if let value {
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 1. 운동 관리

struct WorkoutManagementView: View {
    @AppStorage("bodyWeight") private var bodyWeight = 70.0
    @AppStorage("age") private var age = 25
    @AppStorage("isMale") private var isMale = true
    @AppStorage(Goals.heightKey) private var heightCm = 172.0
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    /// Body weight shown in the display unit: 0.5 kg or 1 lb steps, stored in kg.
    private var bodyWeightValues: [Double] {
        unit == .kg ? stride(from: 30.0, through: 200, by: 0.5).map { $0 } : stride(from: 66.0, through: 440, by: 1).map { $0 }
    }

    private var displayBodyWeight: Binding<Double> {
        Binding(
            get: {
                let step = unit == .kg ? 0.5 : 1
                let value = (unit.fromKg(bodyWeight) / step).rounded() * step
                return min(max(value, bodyWeightValues.first ?? value), bodyWeightValues.last ?? value)
            },
            set: { bodyWeight = unit.toKg($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    RoutineSettingsView()
                } label: {
                    Label("분할 루틴 · 주간 목표", systemImage: "target")
                }
                NavigationLink {
                    GoalsSettingsView()
                } label: {
                    Label("다이어트 · 활동 목표", systemImage: "flame")
                }
            }

            Section {
                WheelPickerRow(title: "몸무게", values: bodyWeightValues, selection: displayBodyWeight) {
                    "\($0.formatted(.number.precision(.fractionLength(unit == .kg ? 1 : 0))))\(unit.symbol)"
                }
                WheelPickerRow(title: "키", values: Array(stride(from: 130.0, through: 220, by: 1)), selection: $heightCm) {
                    "\(Int($0))cm"
                }
                WheelPickerRow(title: "나이", values: Array(10...90), selection: $age) {
                    String(localized: "\($0)세")
                }
                Picker("성별", selection: $isMale) {
                    Text("남성").tag(true)
                    Text("여성").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("내 정보")
            } footer: {
                Text("칼로리는 심박수가 있으면 심박수·몸무게·나이·성별로, 없으면 근력 운동 평균 강도로 추정해요. 건강 앱에 체중이 기록되면 최신 체중으로 자동으로 바뀌어요.")
            }
        }
        .navigationTitle("운동 관리")
    }
}

// MARK: - 2. 위젯

struct WidgetSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    WidgetPreview(size: .small)
                    WidgetPreview(size: .medium)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("위젯 추가 방법") {
                Label("홈 화면의 빈 곳을 길게 누르세요", systemImage: "1.circle.fill")
                Label("왼쪽 위 '편집' → '위젯 추가'를 누르세요", systemImage: "2.circle.fill")
                Label("'세트 카운터'를 찾아 크기를 고르세요", systemImage: "3.circle.fill")
            }

            Section {
                Button("위젯 새로고침", systemImage: "arrow.clockwise") {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } footer: {
                Text("위젯은 오늘의 루틴과 이번 주 목표 진행도를 보여줘요. 운동을 마치면 자동으로 갱신돼요.")
            }

            Section {
                if ProStore.shared.isPro {
                    Label("칼로리 위젯과 잠금 화면 위젯을 쓸 수 있어요", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.orange)
                } else {
                    ProLockedButton(title: "칼로리 위젯 · 잠금 화면 위젯", systemImage: "lock.fill", feature: .personalize)
                }
            } footer: {
                Text("칼로리 위젯은 오늘 먹은 칼로리와 남은 양을, 잠금 화면 위젯은 오늘의 루틴과 칼로리를 보여줘요.")
            }
        }
        .navigationTitle("위젯")
    }
}

/// In-app mock of the home screen widget, drawn from the same snapshot the widget reads.
private struct WidgetPreview: View {
    enum Size { case small, medium }
    let size: Size

    var body: some View {
        let snapshot = WidgetSnapshot.read() ?? .placeholder
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.splitLabel).font(.caption2).foregroundStyle(.secondary)
            Text(snapshot.todayName(at: Date())).font(.headline).lineLimit(1)
            Spacer(minLength: 0)
            if size == .medium {
                HStack(spacing: 4) {
                    ForEach(Array(snapshot.weekDone.enumerated()), id: \.offset) { _, done in
                        Circle().fill(done ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            Text("이번 주 \(snapshot.weeklyDays)/\(snapshot.weeklyGoal)일").font(.caption.bold())
        }
        .padding(12)
        .frame(width: size == .small ? 140 : 180, height: 140, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

// MARK: - 3. 언어

struct LanguageSettingsView: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue
    @State private var showRestartNotice = false

    var body: some View {
        Form {
            Section {
                Picker("언어", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("앱을 완전히 종료했다가 다시 열면 적용돼요.")
            }

            Section {
                Button("iPhone 설정에서 변경", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle("언어")
        .onChange(of: language) { _, newValue in
            (AppLanguage(rawValue: newValue) ?? .system).apply()
            showRestartNotice = true
        }
        .alert("언어를 바꿨어요", isPresented: $showRestartNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("앱을 다시 열면 새 언어로 보여요.")
        }
    }
}

// MARK: - 4. 테마

struct ThemeSettingsView: View {
    @AppStorage("theme") private var theme = ThemeChoice.system.rawValue
    @AppStorage("accent") private var accent = AccentChoice.blue.rawValue
    @State private var paywall: ProFeature?

    private let store = ProStore.shared

    /// Without Pro only the defaults can be picked; the rest open the paywall.
    private var themeSelection: Binding<String> {
        Binding(
            get: { ThemeChoice.effective(theme).rawValue },
            set: { newValue in
                if store.isPro || newValue == ThemeChoice.system.rawValue { theme = newValue } else { paywall = .personalize }
            }
        )
    }

    var body: some View {
        let current = AccentChoice.effective(accent)
        Form {
            Section {
                Picker("화면 모드", selection: themeSelection) {
                    ForEach(ThemeChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                HStack {
                    Text("화면 모드")
                    if !store.isPro { ProBadge() }
                }
            } footer: {
                if !store.isPro {
                    Text("Pro가 없으면 iPhone의 라이트·다크 설정을 따라가요.")
                }
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            if store.isPro || choice == .blue { accent = choice.rawValue } else { paywall = .personalize }
                        } label: {
                            Circle()
                                .fill(choice.color.gradient)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if current == choice {
                                        Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white)
                                    } else if !store.isPro, choice != .blue {
                                        Image(systemName: "lock.fill").font(.caption2.bold()).foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(choice.title))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("강조 색상")
                    if !store.isPro { ProBadge() }
                }
            }
        }
        .navigationTitle("테마")
        .proPaywall($paywall)
    }
}

// MARK: - 7. 표시

struct DisplaySettingsView: View {
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("showMetrics") private var showMetrics = true
    @AppStorage("showElapsed") private var showElapsed = true
    @AppStorage("hapticsOn") private var hapticsOn = true

    var body: some View {
        Form {
            Section {
                Toggle("운동 중 화면 켜두기", isOn: $keepScreenOn)
            } footer: {
                Text("켜두면 운동 화면에서 자동 잠금이 되지 않아요. 배터리를 더 사용해요.")
            }
            Section("운동 화면") {
                Toggle("심박수 · 칼로리 표시", isOn: $showMetrics)
                Toggle("운동 시간 표시", isOn: $showElapsed)
                Toggle("버튼 햅틱", isOn: $hapticsOn)
            }
        }
        .navigationTitle("표시")
    }
}

// MARK: - 8. 휴식 알림

struct RestAlarmSettingsView: View {
    @AppStorage("alarmVolume") private var alarmVolume = 0.8
    @AppStorage("vibrationOn") private var vibrationOn = true
    @AppStorage(AlarmSound.key) private var soundRaw = AlarmSound.beeps.rawValue
    @AppStorage("alarmDuration") private var alarmDuration = 4

    private var sound: AlarmSound { AlarmSound(rawValue: soundRaw) ?? .beeps }

    var body: some View {
        Form {
            Section("알림음") {
                Picker("소리", selection: $soundRaw) {
                    ForEach(AlarmSound.allCases) { Text($0.title).tag($0.rawValue) }
                }
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $alarmVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Button("소리 미리 듣기", systemImage: "play.circle") {
                    AlarmPlayer.shared.preview(sound: sound, volume: Float(alarmVolume))
                }
            }

            Section {
                Picker("울리는 시간", selection: $alarmDuration) {
                    ForEach([3, 4, 5, 10], id: \.self) { Text("\($0)초").tag($0) }
                }
                Toggle("진동", isOn: $vibrationOn)
            } footer: {
                Text("알람이 울리는 동안만 음악이 일시정지되고, 끝나면 다시 재생돼요. 화면이 잠겨 있으면 시스템 알람으로 울려요.")
            }
        }
        .navigationTitle("휴식 알림")
        .onDisappear { AlarmPlayer.shared.stop() }
    }
}

// MARK: - 11. 지원 및 피드백

struct SupportView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Button("앱 리뷰 남기기", systemImage: "star.bubble") {
                    // Apple asks apps to send a button tap to the App Store review page;
                    // the system prompt is rate-limited and may not appear.
                    if let url = AppInfo.writeReviewURL { openURL(url) } else { requestReview() }
                }
                Button("피드백 보내기", systemImage: "lightbulb") {
                    mail(subject: String(localized: "[세트 카운터] 피드백"))
                }
                Button("문의하기", systemImage: "envelope") {
                    mail(subject: String(localized: "[세트 카운터] 문의"))
                }
            } footer: {
                Text("메일 앱이 열리고 앱 버전과 기기 정보가 자동으로 들어가요.\n\(AppInfo.supportEmail)")
            }
        }
        .navigationTitle("지원 및 피드백")
    }

    private func mail(subject: String) {
        let device = UIDevice.current
        let body = "\n\n---\nApp \(AppInfo.version) (\(AppInfo.build))\n\(device.model) · iOS \(device.systemVersion)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url { openURL(url) }
    }
}

// MARK: - 12. 정보

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("버전", value: AppInfo.version)
                LabeledContent("빌드", value: AppInfo.build)
            }

            ForEach(AppInfo.changelog, id: \.version) { entry in
                Section("버전 \(entry.version)") {
                    ForEach(Array(entry.notes.enumerated()), id: \.offset) { _, note in
                        Label(note, systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                Label("모든 운동 기록은 이 iPhone에만 저장돼요. 건강 앱 저장은 직접 허용한 경우에만 해요.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("개인정보 처리방침", systemImage: "doc.text")
                }
            } header: {
                Text("개인정보")
            }
        }
        .navigationTitle("정보")
    }
}
