import SwiftUI

/// Editors occupy the full presentation so navigation and scrolling share a stable size.
struct FocusEditorSheet: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationSizing(.page)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// A short decision sheet, with scrolling space when text needs a larger presentation.
struct FocusEndConfirmation: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var compactHeight = FocusTheme.Layout.compactConfirmationHeight

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { confirmation }
                .modifier(FocusEditorSheet())
        } else {
            confirmation
                .presentationDetents([.height(compactHeight)])
                .presentationDragIndicator(.visible)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.sectionSpacing) {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
                Text("집중을 여기서 끝낼까요?")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FocusTheme.Palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("endConfirmation")
                Text("지금 끝내면 이 세션은 집중 시간으로 기록되지 않아요.")
                    .foregroundStyle(FocusTheme.Palette.secondaryText)
            }
            VStack(spacing: FocusTheme.Layout.inlineSpacing) {
                Button { dismiss() } label: {
                    Text("계속 집중하기")
                        .frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget)
                }
                .modifier(FocusPrimaryAction())
                .modifier(ProminentLabel())
                Button(role: .destructive) {
                    model.end()
                    dismiss()
                } label: {
                    Text("종료하기")
                        .foregroundStyle(FocusTheme.Palette.error)
                        .frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget)
                }
                .modifier(FocusSecondaryAction())
            }
            .modifier(FocusGlassGroup())
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FocusTheme.Layout.screenInset)
        .padding(.vertical, FocusTheme.Layout.sectionSpacing)
    }
}
