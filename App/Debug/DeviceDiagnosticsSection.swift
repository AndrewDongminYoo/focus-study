#if DEBUG
import SwiftUI

struct DeviceDiagnosticsSection: View {
    let diagnostics: DeviceDiagnostics
    let model: FocusModel
    /// The Focus filter handler of this process and `FocusStudyFilter.reading()`, from the app.
    let filterHandler: FocusFilterHandler?
    let readFilter: () async -> FocusFilterReading
    let openEverydayPicker: () -> Void
    @State private var replayFailed = false
    @State private var filterReading: FocusFilterReading?
    @State private var callLog: [String] = []
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
            if diagnostics.canProbeRegistration {
                Button("등록 시간 비교") { diagnostics.runRegistrationProbe() }.accessibilityIdentifier("diagnosticRegistrationProbe")
            }
            if diagnostics.canApplyEveryday {
                Button("매일 제한 store에 선택 적용(합집합 검사 없음)", action: openEverydayPicker).accessibilityIdentifier("diagnosticEverydayApply")
            }
            if let message = diagnostics.message { Text(message).font(.footnote) }
            if replayFailed { Text("콜백을 전달하지 못했습니다. 세션 상태를 다시 확인해 주세요.").foregroundStyle(FocusTheme.Palette.error) }
        }
        Section("Focus 필터 진단") {
            if let filterHandler {
                Button("Focus 켜짐 전달") { Task { await filterHandler.focusDidChange(startsSession: true); callLog = model.services.settings.filterCallLog } }
                    .accessibilityIdentifier("diagnosticFilterOn")
                Button("Focus 꺼짐 전달") { Task { await filterHandler.focusDidChange(startsSession: false); callLog = model.services.settings.filterCallLog } }
                    .accessibilityIdentifier("diagnosticFilterOff")
            }
            Button("current 읽기") { Task { filterReading = await readFilter() } }.accessibilityIdentifier("diagnosticFilterRead")
            if let filterReading { Text("current: \(String(describing: filterReading))").font(.footnote) }
            ForEach(Array(callLog.reversed().enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
        }
        .onAppear { callLog = model.services.settings.filterCallLog }
    }
}
#endif
