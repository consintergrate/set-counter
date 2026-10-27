import CoreBluetooth
import SwiftUI

struct HeartRateSettingsView: View {
    @AppStorage("useHealthKit") private var useHealthKit = true
    @AppStorage(HealthWorkout.useWatchKey) private var useWatch = true

    private let bluetooth = BluetoothHeartRate.shared
    private let monitor = HeartRateMonitor.shared

    var body: some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("현재 심박수") {
                        if let bpm = monitor.currentBPM(at: context.date) {
                            Text("\(bpm) bpm").monospacedDigit().bold().foregroundStyle(.red)
                        } else {
                            Text("신호 없음").foregroundStyle(.secondary)
                        }
                    }
                }
                if let source = monitor.source {
                    LabeledContent("마지막 신호", value: source)
                }
            }

            Section {
                Toggle("Apple Watch · AirPods 심박수", isOn: $useHealthKit)
                    .onChange(of: useHealthKit) { _, isOn in
                        if isOn { Task { await HealthWorkout.shared.requestAuthorization() } }
                    }
                if useHealthKit {
                    if ProStore.shared.isPro {
                        Toggle("Apple Watch 앱으로 실시간 측정", isOn: $useWatch)
                    } else {
                        ProLockedButton(title: "Apple Watch 앱으로 실시간 측정", feature: .watch)
                    }
                }
            } header: {
                Text("Apple 기기")
            } footer: {
                Text("운동을 시작하면 Apple Watch의 세트 카운터 앱이 함께 켜져 몇 초마다 심박수를 보내고, 휴식이 끝나면 손목을 톡 쳐서 알려줘요. 워치에서 운동을 따로 켤 필요는 없어요. AirPods Pro 3·Powerbeats Pro 2는 착용만 하면 돼요.")
            }

            Section {
                if let connected = bluetooth.connected {
                    LabeledContent(connected.name ?? String(localized: "심박 센서")) {
                        Text("연결됨").foregroundStyle(.green)
                    }
                    Button("연결 해제", role: .destructive) { bluetooth.forget() }
                } else if let connecting = bluetooth.connecting {
                    LabeledContent(connecting.name ?? String(localized: "심박 센서")) {
                        ProgressView()
                    }
                    Button("연결 취소", role: .destructive) { bluetooth.forget() }
                } else {
                    Button(bluetooth.isScanning ? String(localized: "찾는 중…") : String(localized: "심박 센서 찾기"), systemImage: "antenna.radiowaves.left.and.right") {
                        bluetooth.startScan()
                    }
                    .disabled(bluetooth.isScanning)
                    ForEach(bluetooth.discovered, id: \.identifier) { peripheral in
                        Button(peripheral.name ?? String(localized: "이름 없는 센서")) { bluetooth.connect(peripheral) }
                    }
                }
            } header: {
                Text("블루투스 심박 센서")
            } footer: {
                Text("Polar·Garmin 같은 가슴 스트랩이나 심박 방송 기능이 있는 기기를 연결할 수 있어요. 한 번 연결하면 다음부터 자동으로 연결돼요.")
            }
        }
        .navigationTitle("심박수 · 칼로리")
        .onAppear { bluetooth.activate() }
        .onDisappear { bluetooth.stopScan() }
    }
}
