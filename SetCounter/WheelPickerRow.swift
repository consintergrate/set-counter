import SwiftUI

/// A row that shows the current value; tapping it opens a scroll wheel in a sheet,
/// and the value only changes when 확인 is tapped.
struct WheelPickerRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    let values: [Value]
    @Binding var selection: Value
    /// Shown instead of the value while nothing has been picked yet.
    var placeholder: String? = nil
    let label: (Value) -> String

    @State private var draft: Value?
    @State private var isPresented = false

    var body: some View {
        Button {
            draft = selection
            isPresented = true
        } label: {
            LabeledContent(title) {
                Text(placeholder ?? label(selection))
                    .monospacedDigit()
                    .bold()
                    .foregroundStyle(.tint)
            }
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Picker(title, selection: Binding(get: { draft ?? selection }, set: { draft = $0 })) {
                    ForEach(values, id: \.self) { value in
                        Text(label(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("확인") {
                            if let draft { selection = draft }
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.height(320)])
        }
    }
}
