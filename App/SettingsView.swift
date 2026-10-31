import SwiftUI

/// Personal settings opened from the timer screen's top-right button.
struct SettingsView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("집중 시간", selection: Binding(get: { model.services.settings.lengthMinutes }, set: { model.services.settings.lengthMinutes = $0 })) {
                        ForEach(FocusLength.allowedMinutes, id: \.self) { Text("\($0)분").tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("lengthPicker")
                } header: { Text("집중 시간") } footer: { Text("바꾼 시간은 다음 집중부터 적용돼요.") }
                #if DEBUG
                if let diagnostics = model.services.diagnostics { DeviceDiagnosticsSection(diagnostics: diagnostics, model: model) }
                #endif
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }
    }
}
