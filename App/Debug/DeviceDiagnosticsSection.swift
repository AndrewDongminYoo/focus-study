#if DEBUG
import SwiftUI

struct DeviceDiagnosticsSection: View {
    let diagnostics: DeviceDiagnostics
    let model: FocusModel
    @State private var replayFailed = false
    var body: some View {
        Section("실기기 진단") {
            Text("실제 Screen Time 등록을 사용하는 진단입니다. 기기 소유자가 동의한 항목으로만 진행해 주세요.")
                .font(.footnote)
            Button("다음 등록 후 실패 주입") { diagnostics.armRegistrationFailure() }
                .disabled(!model.canStart || diagnostics.monitoring.isFailureArmed)
                .accessibilityIdentifier("diagnosticRegistrationFailure")
            Button("현재 세션 콜백 저장") {
                if let current = model.current { diagnostics.capture(current) }
            }.disabled(!model.isActive).accessibilityIdentifier("diagnosticCapture")
            Button("이전 세션 콜백 전달") {
                do { try diagnostics.replay(current: model.current); replayFailed = false }
                catch { replayFailed = true }
                model.refresh()
            }.disabled(!diagnostics.canReplay(current: model.current)).accessibilityIdentifier("diagnosticReplay")
            if let message = diagnostics.message { Text(message).font(.footnote) }
            if replayFailed { Text("콜백을 전달하지 못했습니다. 세션 상태를 다시 확인해 주세요.").foregroundStyle(.red) }
        }
    }
}
#endif
