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
                Section {
                    NavigationLink { EverydaySettingsView(model: model) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("시간과 앱 정하기")
                            Text(EverydaySettingsModel.statusLine(model.everydayStatus, calendar: model.services.engine.calendar)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("everydayRow")
                } header: { Text("매일 제한") } footer: { Text("정한 시간대에 매일 앱과 웹사이트를 제한해요.") }
                #if DEBUG
                if let diagnostics = model.services.diagnostics { DeviceDiagnosticsSection(diagnostics: diagnostics, model: model) }
                #endif
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .onAppear { model.refreshEveryday() }
            // The row's status changes at a range or window boundary while the sheet stays open, also with no focus tick.
            .task(id: model.everydayStatus) {
                await EverydaySettingsModel.followStatus({ model.everydayStatus }, now: Date.init) { model.refreshEveryday() }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }
    }
}
