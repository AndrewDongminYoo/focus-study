import SwiftUI

/// The temporary paywall that the start action opens while paid access is `locked` (docs/specs/2026-11-24-paid-access-design.md).
/// It follows the element order and the copy of the Figma draft (node 25:2) with system styles; issue #247 applies the final design.
/// Before the trial starts it states the trial length, what stops at its end and the unlock price (Guideline 3.1.1).
struct PaidAccessSheet: View {
    let store: PaidAccessStore
    @Environment(\.dismiss) private var dismiss
    /// A trial that was used once cannot start again, so its badge, button and notice go away and the purchase becomes the primary action.
    private var canStartTrial: Bool { store.facts?.trial == nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introduction
                    features
                    conditions
                    actions
                    if canStartTrial { trialNotice }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.accessibilityIdentifier("paywallClose") } }
        }
        .accessibilityIdentifier("paywall")
        .task { if store.unlockPrice == nil { await store.loadPrice() } }
        // The sheet closes when access is granted, also when a refresh granted it before the first render; the person then taps the start action again.
        .onChange(of: store.state, initial: true) { _, state in if state == .granted { dismiss() } }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canStartTrial {
                Text("3일 무료 체험").font(.subheadline.bold()).foregroundStyle(.tint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            Text("순공 시간을\n차곡차곡 쌓아요").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("집중 세션으로 재고, 캘린더와 회고로 돌아봐요.").foregroundStyle(.secondary)
        }
    }

    private var features: some View {
        VStack(spacing: 12) {
            feature("집중 세션", "타이머가 도는 동안 고른 앱을 막아요.")
            feature("순공 캘린더와 주간 회고", "날마다 쌓인 순공 시간을 보고 한 주를 돌아봐요.")
        }
    }
    private func feature(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        // A fill, not a background color: the sheet's own background is white in light mode, so a grouped background disappears there.
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if canStartTrial {
                Text("시작하면 3일 동안 무료예요.").font(.subheadline.bold())
                Text("체험이 끝나면 위 기능이 잠기고, 자동으로 결제되지 않아요.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("매일 제한은 3일이 지나도 계속 쓸 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if canStartTrial {
                // It starts only after the unlock price is on the sheet (Guideline 3.1.1).
                Button { Task { await store.startTrial() } } label: { Text("3일 무료 체험 시작하기").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(store.unlockPrice == nil)
                    .accessibilityIdentifier("paywallTrial")
            }
            purchaseButton
            if store.unlockPrice == nil {
                Button("가격 다시 확인") { Task { await store.loadPrice() } }.accessibilityIdentifier("paywallPriceRetry")
            }
            Text("한 번 구매하면 계속 쓸 수 있어요. 구독이 아니에요.").font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("구매 복원하기") { Task { await store.restore() } }.accessibilityIdentifier("paywallRestore")
            if let message = store.message {
                Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("paywallMessage")
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(store.isWorking)
    }
    /// The price is the one that the store returns, never a constant in code.
    @ViewBuilder private var purchaseButton: some View {
        let label = Text(store.unlockPrice.map { "구매하기 · \($0)" } ?? "구매하기 · 가격 확인 중").frame(maxWidth: .infinity)
        if canStartTrial {
            Button { Task { await store.purchaseUnlock() } } label: { label }
                .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("paywallPurchase")
        } else {
            Button { Task { await store.purchaseUnlock() } } label: { label }
                .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("paywallPurchase")
        }
    }

    private var trialNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("무료 체험 안내").font(.footnote.bold()).foregroundStyle(.secondary)
            Text("체험은 0원짜리 앱 내 구입 ‘3-day Trial’로 시작해요. 3일이 지난 뒤에는 구매하면 다시 쓸 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
