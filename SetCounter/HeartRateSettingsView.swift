import CoreBluetooth
import SwiftUI

struct HeartRateSettingsView: View {
    @AppStorage("useHealthKit") private var useHealthKit = true

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
            } header: {
                Text("Apple 기기")
            } footer: {
                Text("AirPods Pro 3·Powerbeats Pro 2는 착용만 하면 돼요. Apple Watch는 워치에서 '근력 운동'을 같이 켜두면 심박수가 자주 들어와요. 마친 운동은 건강 앱에도 저장돼요.")
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
