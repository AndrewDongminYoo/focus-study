import AppIntents

/// The FocusStudy Focus filter (spec "The filter intent"). It is compiled into the app target only, and it is the only file that imports `AppIntents`.
/// The system calls `perform()` with the default values when the Focus turns off, so the default `false` means "no session".
struct FocusStudyFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "집중 시간"
    static let description: IntentDescription? = IntentDescription("이 집중 모드를 켜면 정한 시간만큼 집중을 시작해요.")
    @Parameter(title: "집중 시작", default: false) var startsSession: Bool
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: startsSession ? LocalizedStringResource("집중 시작 켬") : LocalizedStringResource("집중 시작 끔"))
    }
    @MainActor func perform() async throws -> some IntentResult {
        await FocusRuntime.focusFilterDidChange(startsSession: startsSession)
        return .result()
    }
    /// `current` for the activation check: `notFound` counts as off; any other error changes nothing.
    static func reading() async -> FocusFilterReading {
        do { return try await current.startsSession ? .on : .off }
        catch SetFocusFilterIntentError.notFound { return .off }
        catch { return .unknown }
    }
}
