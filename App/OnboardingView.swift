import SwiftUI

/// Setup before the timer: intro, Screen Time access, focus-session selection, focus length.
struct OnboardingView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: OnboardingStep
    @State private var choosing = false
    init(model: FocusModel, start: OnboardingStep) { self.model = model; _step = State(initialValue: start) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.sectionSpacing) {
                Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(FocusTheme.Palette.secondaryText)
                    .accessibilityLabel("설정 진행")
                    .accessibilityValue("\(OnboardingStep.allCases.count)단계 중 \(step.rawValue + 1)단계")
                    .accessibilityIdentifier("onboardingProgress")
                content
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FocusTheme.Layout.screenInset)
            .padding(.vertical, FocusTheme.Layout.sectionSpacing)
        }
        .id(step)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: FocusTheme.Layout.controlSpacing) {
                if step != .intro {
                    Button("이전") { if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous } }
                        .modifier(FocusSecondaryAction()).accessibilityIdentifier("onboardingBack")
                }
                Spacer()
                if step == .length {
                    Button("시작하기") { model.completeOnboarding() }.modifier(FocusPrimaryAction()).modifier(ProminentLabel()).accessibilityIdentifier("onboardingFinish")
                } else {
                    Button("다음") { if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next } }
                        .modifier(FocusPrimaryAction()).modifier(ProminentLabel()).disabled(!canAdvance).accessibilityIdentifier("onboardingNext")
                }
            }
            .modifier(FocusGlassGroup())
            .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.vertical, FocusTheme.Layout.controlSpacing)
            .background(FocusTheme.Palette.surface)
        }
        .sheet(isPresented: $choosing) { selectionEditor }
        .task { model.refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { model.refresh() } }
        // Forward moves stay with the person; losing access moves back so the person is not left past the permission step.
        // `checking` is not a loss of access, so it keeps the step.
        .onChange(of: model.access) { _, access in if (access == .denied || access == .notRequested) && step.rawValue > OnboardingStep.permission.rawValue { step = .permission } }
    }
    private var canAdvance: Bool {
        switch step {
        case .intro: true
        case .permission: model.access == .approved
        case .selection: model.counts.apps + model.counts.websites > 0
        case .length: true
        }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            Text("공부하는 동안 방해 요소를 잠시 멈춰요").font(.title.weight(.bold))
            Label("정한 시간 동안 고른 앱과 웹사이트를 제한해요.", systemImage: "timer").accessibilityIdentifier("purpose")
            Label("앱을 제한하고 사용 보고서를 보여 주려면 스크린 타임 권한이 필요해요.", systemImage: "hourglass")
            Label("데이터는 기기에만 저장돼요", systemImage: "lock.iphone")
        case .permission:
            switch model.access {
            case .approved:
                Text("스크린 타임 권한을 허용했어요").font(.title.weight(.bold))
                Text("다음 단계에서 집중하는 동안 제한할 앱을 골라요.").foregroundStyle(FocusTheme.Palette.secondaryText)
            case .notRequested, .checking:
                Text("스크린 타임 권한이 필요해요").font(.title.weight(.bold))
                Text("집중하는 동안 고른 앱을 제한하려면 권한을 허용해 주세요.").foregroundStyle(FocusTheme.Palette.secondaryText)
                Button("권한 허용하기") { Task { await model.services.authorization.requestIndividual(); model.refresh() } }
                    .modifier(FocusPrimaryAction()).modifier(ProminentLabel()).accessibilityIdentifier("authorize")
            case .denied:
                Text("스크린 타임 권한이 꺼져 있어요").font(.title.weight(.bold))
                Text("설정 앱에서 이 앱의 스크린 타임 권한을 켜면 이어서 시작할 수 있어요.").foregroundStyle(FocusTheme.Palette.secondaryText)
                Link("설정 열기", destination: URL(string: UIApplication.openSettingsURLString)!).accessibilityIdentifier("settings")
            }
        case .selection:
            Text("집중하는 동안 제한할 앱을 골라요").font(.title.weight(.bold))
            Text("앱 \(model.counts.apps)개 · 웹사이트 \(model.counts.websites)개 선택").monospacedDigit().foregroundStyle(FocusTheme.Palette.secondaryText)
            Button("제한할 항목 고르기") { choosing = true }.modifier(FocusSecondaryAction()).accessibilityIdentifier("chooseSelection")
        case .length:
            Text("한 번에 몇 분 집중할까요?").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
                Text("집중 시간")
                Picker("집중 시간", selection: Binding(get: { model.services.settings.lengthMinutes }, set: { model.services.settings.lengthMinutes = $0 })) {
                    ForEach(FocusLength.allowedMinutes, id: \.self) { Text("\($0)분").tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("lengthPicker")
            }
            Text("설정에서 언제든 바꿀 수 있어요.").font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
        }
    }
    @ViewBuilder private var selectionEditor: some View {
        #if DEBUG
        if let fixture = model.services.selection as? FixtureSelection { FixtureSelectionEditor(repository: fixture) }
        else { SelectionEditor(model: model) }
        #else
        SelectionEditor(model: model)
        #endif
    }
}
