import SwiftUI

/// The paywall and the trial offer (docs/specs/2026-11-26-paywall-design.md): a card sheet like the weekly review form A,
/// in which the reassurance band is the darkest part. Before the trial starts it states the trial length, the features that need
/// a purchase after it and the unlock price (Guideline 3.1.1).
struct PaidAccessSheet: View {
    let store: PaidAccessStore
    /// The focus length of the start that a confirmed trial or purchase continues; `nil` for an entry that holds no start request,
    /// and after this sheet dropped it.
    var startMinutes: Int?
    /// A trial or purchase confirmed inside this sheet, with access `granted`; the sheet closes right after it.
    var onConfirmed: () -> Void = {}
    /// A pending purchase, a cancel or a failure: no later result of this sheet continues the start.
    var onDropStart: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// A fixed size, as on the review explanation: a tile that scales with the text pushes the reassurance band below the fold at an accessibility size.
    private let markHeight: CGFloat = 40, tileSize: CGFloat = 64
    /// True while this sheet's own trial, purchase or restore runs. Access that opens during it does not close the sheet by itself,
    /// so a confirmed result is reported before the close.
    @State private var acting = false
    /// The form at the start of this sheet's own trial, purchase or restore, so a result does not change the text while the sheet closes.
    /// It is cleared when the action ends with the sheet open, so facts that the store confirms later reach the open sheet.
    @State private var frozenTrialUsed: Bool?
    /// The trial ended, or a trial purchase exists: the trial cannot start again (contract item 3).
    private var trialUsed: Bool { frozenTrialUsed ?? (store.facts?.trial != nil || store.facts?.trialStartedAt != nil) }
    /// The price that the store returns; never a constant in code.
    private var price: String? { store.unlockPrice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.controlSpacing) {
                HStack {
                    Spacer(minLength: 0)
                    // "나중에" drops the start request first, so a result that arrives during the close does not confirm it.
                    Button { onDropStart(); dismiss() } label: {
                        Text("나중에").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText).fixedSize()
                            .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("paywallClose")
                }
                // The mark on a navy tile, as in the app icon and the review explanation: its cream ring does not show on the light canvas.
                ColonMark(height: markHeight).frame(width: tileSize, height: tileSize)
                    .background(RoundedRectangle(cornerRadius: 16).fill(FocusTheme.Room.background))
                introduction
                band
                card
                actions
            }
            .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.top, FocusTheme.Layout.relatedSpacing).padding(.bottom, FocusTheme.Layout.sectionSpacing)
        }
        .background(FocusTheme.Screen.canvas.ignoresSafeArea())
        .accessibilityIdentifier("paywall")
        .modifier(FocusEditorSheet())
        // A swipe cannot close the sheet while its own action runs, so its result never lands during a close that kept the start request.
        .interactiveDismissDisabled(acting)
        .task { if price == nil { await store.loadPrice() } }
        // Access that opens outside this sheet's own actions, such as an approved purchase from `Transaction.updates`, closes the sheet
        // and starts nothing; a restore that opens access closes it the same way.
        .onChange(of: PaywallOutcome.closesByItself(access: store.state, acting: acting), initial: true) { _, closes in if closes { dismiss() } }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            Text(trialUsed ? "3일 체험이 끝났어요" : "집중 타이머를 3일 동안 무료로 써보세요").font(.title2.bold()).foregroundStyle(FocusTheme.Screen.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader).accessibilityIdentifier("paywallTitle")
            if let startMinutes {
                Text(trialUsed ? "평생권을 구매하면, 하려던 \(startMinutes)분 집중이 이어져요." : "무료 체험을 시작하면, 하려던 \(startMinutes)분 집중이 이어져요.")
                    .font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywallStartLine")
            }
        }
    }

    /// The reassurance band: the most prominent part after the title. In the dark appearance the canvas is nearly the same navy,
    /// so an amber border keeps it the most prominent, as on the weekly review's note card.
    private var band: some View {
        let lines = trialUsed
            ? ["구매하지 않아도 평소 앱·웹사이트 제한은 계속 쓸 수 있어요.", "지금까지의 기록은 기기에 그대로 있어요."]
            : ["체험이 끝나도 자동으로 결제되지 않아요.", "구매하지 않아도 평소 앱·웹사이트 제한은 계속 쓸 수 있어요."]
        return VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.inlineSpacing) {
                    Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(FocusTheme.Room.marker).accessibilityHidden(true)
                    Text(line).font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Room.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(FocusTheme.Room.background))
        .overlay(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).strokeBorder(FocusTheme.Room.marker, lineWidth: scheme == .dark ? 1.5 : 0))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            Text(trialUsed ? "평생권으로 다시 쓸 수 있어요" : "3일이 지나면 구매가 필요해요").font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
                ForEach(["집중 타이머와 휴식", "순공 캘린더", "주간 회고와 공유 이미지"], id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.inlineSpacing) {
                        Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(FocusTheme.Screen.accentText).accessibilityHidden(true)
                        Text(feature).font(.subheadline).foregroundStyle(FocusTheme.Screen.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.inlineSpacing) {
                    priceLabel
                    Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                    priceValue
                }
                VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                    priceLabel
                    priceValue
                }
            }
            if price == nil {
                Button("가격 다시 불러오기") { Task { await store.loadPrice() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(FocusTheme.Screen.accentText)
                    .frame(minHeight: FocusTheme.Layout.minimumTapTarget).accessibilityIdentifier("paywallPriceRetry")
            }
            Text("구독이 아니에요. 한 번 사면 계속 써요.").font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
        .modifier(FocusCard())
    }
    private var priceLabel: some View {
        Text("평생권 구매").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.ink).fixedSize()
    }
    @ViewBuilder private var priceValue: some View {
        if let price {
            Text(price).font(.headline).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink).fixedSize().accessibilityIdentifier("paywallPrice")
        } else {
            Text("가격을 불러오고 있어요").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywallPriceLoading")
        }
    }

    /// The buttons stay at the bottom of the content; at an accessibility text size the sheet scrolls to them.
    private var actions: some View {
        VStack(spacing: 11) {
            if !trialUsed {
                Button("3일 무료로 써보기") { act { await store.startTrial() } }
                    .buttonStyle(fill(primary: true)).disabled(price == nil || store.isWorking).accessibilityIdentifier("paywallTrial")
            }
            Button(price.map { "평생권 \($0) 구매하기" } ?? "평생권 구매하기") { act { await store.purchaseUnlock() } }
                .buttonStyle(fill(primary: trialUsed)).disabled(price == nil || store.isWorking).accessibilityIdentifier("paywallPurchase")
            Button("구매 복원") { restore() }
                .font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
                .frame(minHeight: FocusTheme.Layout.minimumTapTarget).disabled(store.isWorking).accessibilityIdentifier("paywallRestore")
            if let message = store.message {
                Text(message).font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("paywallMessage")
            }
        }
        .frame(maxWidth: .infinity)
    }
    /// The primary button: `AccentColor` with `AccentLabel` text, white in light and navy in dark; the secondary one: a card with accent text.
    private func fill(primary: Bool) -> FocusFillButtonStyle {
        primary ? FocusFillButtonStyle(fill: FocusTheme.Palette.accent, label: FocusTheme.Palette.onAccent)
            : FocusFillButtonStyle(fill: FocusTheme.Screen.card, label: FocusTheme.Screen.accentText)
    }

    private func act(_ action: @escaping () async -> PaidActionResult) {
        acting = true; frozenTrialUsed = trialUsed
        Task {
            switch PaywallOutcome(await action(), access: store.state) {
            case .continueStart:
                onConfirmed(); dismiss(); acting = false
                return
            case .dropStart: onDropStart()
            case .none: break
            }
            acting = false; frozenTrialUsed = nil
        }
    }
    /// A restore opens access and closes the sheet, and never continues a start (contract item 6).
    private func restore() {
        acting = true; frozenTrialUsed = trialUsed
        Task {
            await store.restore()
            acting = false
            if store.state != .granted { frozenTrialUsed = nil }
        }
    }
}
