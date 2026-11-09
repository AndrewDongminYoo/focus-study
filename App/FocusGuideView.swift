import SwiftUI

/// The Focus setup guide, opened from the settings sheet (spec "Settings guide content"). Text only: no button opens the Focus settings.
struct FocusGuideView: View {
    let settings: FocusSettings
    var body: some View {
        List {
            Section("하는 일") {
                FocusGuideRow(icon: "moon.fill", title: "고른 집중 모드를 켜면 집중을 시작해요", detail: "정한 집중 시간과 제한할 앱을 그대로 써요.")
                FocusGuideRow(icon: "bell.fill", title: "알림은 iOS가 정해요", detail: "그 집중 모드의 알림 설정을 따라요. 이 앱은 알림이나 집중 모드 설정을 바꾸지 않아요.")
                Text("허용한 사람과 앱이 아니어도 이런 알림은 올 수 있어요.")
                    .font(.subheadline).foregroundStyle(FocusTheme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                FocusGuideRow(icon: "clock.badge.exclamationmark", title: "시간 민감 알림", detail: "집중 모드에서 허용했을 때")
                FocusGuideRow(icon: "phone.arrow.down.left", title: "반복 전화", detail: "집중 모드에서 허용했을 때")
                FocusGuideRow(icon: "person.crop.circle.badge.exclamationmark", title: "긴급 우회를 켠 연락처", detail: nil)
                FocusGuideRow(icon: "sparkles", title: "Apple Intelligence가 고른 중요한 알림", detail: "이 기능을 켜 두었을 때")
            }
            if let refusal = settings.lastFilterRefusal {
                Section("지난번 시작") {
                    Text("\(refusal.at.formatted(date: .abbreviated, time: .shortened))에 집중 모드가 켜졌지만 집중을 시작하지 않았어요. \(Self.advice(refusal.reason))")
                        .accessibilityIdentifier("focusFilterRefusal")
                }
            }
            Section("설정 방법") {
                FocusGuideRow(icon: "1.circle.fill", title: "집중 모드 만들기", detail: "설정 앱의 집중 모드에서 공부할 때 쓸 집중 모드를 만들어요. 예: 공부")
                FocusGuideRow(icon: "2.circle.fill", title: "알림 정하기", detail: "알림을 받을 사람과 앱, 반복 전화를 받을지 정해요.")
                FocusGuideRow(icon: "3.circle.fill", title: "필터 추가하기", detail: "필터 추가에서 \(Self.appName) 항목을 고르고 집중 시작을 켜요.")
            }
            Section("알아 둘 점") {
                FocusGuideRow(icon: "repeat", title: "켤 때마다 한 번 시작해요", detail: "켜 둔 채 집중이 끝나면 다음에 켤 때 다시 시작해요.")
                FocusGuideRow(icon: "stop.circle", title: "끄면 집중 모드로 시작한 집중만 끝나요", detail: "집중 시작하기 버튼으로 시작한 집중은 그대로 이어져요.")
                FocusGuideRow(icon: "calendar.badge.clock", title: "예약한 집중 모드도 똑같아요", detail: nil)
                FocusGuideRow(icon: "app.badge", title: "허용한 앱은 모든 알림을 보내요", detail: nil)
                FocusGuideRow(icon: "exclamationmark.triangle", title: "긴급 알림은 iOS 설정을 따라요", detail: "재난 문자 같은 긴급 알림은 이 앱이 바꾸지 않아요.")
            }
        }
        .accessibilityIdentifier("focusGuide")
        .navigationTitle("집중 모드 연결").navigationBarTitleDisplayMode(.inline)
    }
    /// The name Settings lists under Add Filter: the bundle display name, so the guide follows a rename.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FocusStudy"
    }
    /// What the person can do about a refused start.
    static func advice(_ reason: FocusFilterRefusal) -> String {
        switch reason {
        case .access: "스크린 타임 권한을 허용하면 다음부터 시작할 수 있어요."
        case .selection: "제한할 앱을 고르면 다음부터 시작할 수 있어요."
        case .busy: "이미 진행 중인 집중이 있었어요. 그 집중을 마치면 다음부터 시작할 수 있어요."
        case .history: "지난 집중 기록을 저장하지 못했어요. 앱을 열면 기록을 다시 저장해요."
        case .error: "집중 상태를 확인하지 못했어요. 앱을 열어 상태를 확인해 주세요."
        }
    }
}

/// One guide row: a decorative icon, a bold short title and an optional detail line, read by VoiceOver as one element.
/// At accessibility text sizes the icon sits above the text so the text keeps the full row width.
private struct FocusGuideRow: View {
    let icon: String
    let title: String
    let detail: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 28
    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.relatedSpacing))
        layout {
            Image(systemName: icon).font(.headline).foregroundStyle(FocusTheme.Palette.accent)
                .frame(width: stacked ? nil : iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                Text(title).font(.headline).foregroundStyle(FocusTheme.Palette.primaryText)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(FocusTheme.Palette.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, FocusTheme.Layout.detailSpacing)
        .accessibilityElement(children: .combine)
    }
}
