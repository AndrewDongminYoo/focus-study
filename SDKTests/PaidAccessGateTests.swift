import XCTest

/// The start gate of the app (docs/specs/2026-11-24-paid-access-design.md, "App gate"): only a confirmed `locked` opens the paywall,
/// at the tap and again inside the start section; a running session continues when access ends.
@MainActor final class PaidAccessGateTests: XCTestCase {
    private final class Paid { var value = PaidAccessState.granted }
    private func model() -> (FocusModel, Paid, ModelTestShield) {
        let shield = ModelTestShield(), paid = Paid()
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.paidAccess = { paid.value }
        let model = FocusModel(services: services, history: ModelTestHistory(acknowledge: engine.acknowledgeTerminal))
        model.completeOnboarding(); model.refresh()
        return (model, paid, shield)
    }

    func testLockedTapOpensThePaywallAndStartsNothing() {
        let (model, paid, shield) = model()
        paid.value = .locked
        // The start control stays enabled and shows no blocker: the tap opens the sheet.
        XCTAssertTrue(model.canStart); XCTAssertNil(model.startBlocker); XCTAssertEqual(model.route, .timer)
        XCTAssertNil(model.requestStart())
        XCTAssertNotNil(model.paywallRequest)
        XCTAssertNil(model.startRequestID); XCTAssertFalse(model.isStarting)
        XCTAssertNil(model.current); XCTAssertFalse(shield.applied)
        model.start()
        XCTAssertNil(model.current)
        model.dismissPaywall(); XCTAssertNil(model.paywallRequest)
    }
    /// Access that ends between the tap and the start section, such as a trial that ends, is read again inside it.
    func testAccessThatEndsBeforeTheStartSectionOpensThePaywall() throws {
        let (model, paid, shield) = model()
        let request = try XCTUnwrap(model.requestStart())
        paid.value = .locked
        model.performPendingStart(request)
        XCTAssertNil(model.current); XCTAssertFalse(shield.applied)
        XCTAssertNotNil(model.paywallRequest)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.startRequestID); XCTAssertNil(model.errorMessage)
    }
    /// `unknown` never opens the paywall, so an earlier user whose first read failed still starts.
    func testUnknownAndGrantedStart() {
        for value in [PaidAccessState.unknown, .granted] {
            let (model, paid, _) = model()
            paid.value = value
            model.start()
            XCTAssertTrue(model.isActive, "\(value)"); XCTAssertNil(model.paywallRequest, "\(value)")
        }
    }
    func testARunningSessionContinuesWhenAccessEnds() {
        let (model, paid, shield) = model()
        model.start(); XCTAssertTrue(model.isActive)
        paid.value = .locked
        model.refresh(); model.tick()
        XCTAssertTrue(model.isActive); XCTAssertTrue(shield.applied); XCTAssertNil(model.paywallRequest)
    }
}
