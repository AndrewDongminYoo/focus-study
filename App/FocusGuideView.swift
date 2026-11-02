import SwiftUI

/// The Focus setup guide, opened from the settings sheet (spec "Settings guide content"). Text only: no button opens the Focus settings.
struct FocusGuideView: View {
    let settings: FocusSettings
    var body: some View {
        List {
            Section {
                Text("고른 집중 모드를 켜면 정한 집중 시간과 제한할 앱으로 집중을 시작해요.")
                Text("알림은 그 집중 모드의 설정에 따라 iOS가 정해요. 이 앱은 알림이나 집중 모드 설정을 바꾸지 않아요.")
            } header: { Text("하는 일") } footer: {
                Text("허용한 사람과 앱이 아니어도 알림이 올 수 있어요. 집중 모드에서 허용하면 시간 민감 알림과 반복 전화가 오고, 긴급 우회를 켠 연락처도 알림을 보낼 수 있어요. Apple Intelligence가 중요한 알림을 골라 주는 기능을 켜 두었다면 그 알림도 올 수 있어요.")
            }
            if let refusal = settings.lastFilterRefusal {
                Section("지난번 시작") {
                    Text("\(refusal.at.formatted(date: .abbreviated, time: .shortened))에 집중 모드가 켜졌지만 집중을 시작하지 않았어요. \(Self.advice(refusal.reason))")
                        .accessibilityIdentifier("focusFilterRefusal")
                }
            }
            Section("설정 방법") {
                Text("1. 설정 앱의 집중 모드에서 공부할 때 쓸 집중 모드를 만들어요. 예: 공부")
                Text("2. 그 집중 모드에서 알림을 받을 사람과 앱, 반복 전화를 받을지 정해요.")
                Text("3. 그 집중 모드의 필터 추가에서 \(Self.appName) 항목을 고르고 집중 시작을 켜요.")
            }
            Section("알아 둘 점") {
                Text("집중 모드를 켤 때마다 집중을 한 번 시작해요. 집중 모드를 켜 둔 채 집중이 끝나면 다음에 집중 모드를 켤 때 다시 시작해요.")
                Text("집중 모드를 끄면 집중 모드로 시작한 집중이 끝나요. 집중 시작하기 버튼으로 시작한 집중은 그대로 이어져요.")
                Text("예약해 둔 집중 모드도 똑같이 동작해요.")
                Text("허용한 앱은 모든 알림을 보내요.")
                Text("재난 문자 같은 긴급 알림은 이 앱이 바꾸지 않고 iOS 설정을 따라요.")
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
