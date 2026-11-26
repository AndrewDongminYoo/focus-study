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

    /// `--paid-access`-like StoreKit for the paywall flow: each purchase result is set by the test, and `approve` delivers a transaction
    /// through the captured `Transaction.updates` handler, as an Ask to Buy approval does.
    @MainActor private final class PaywallStoreKit: PaidAccessStoreKit {
        var purchaseResult: Result<PaidPurchaseOutcome, Error>?
        var syncAdds: [String: PaidPurchase] = [:]
        private var reads: [String: PaidPurchase] = [:]
        private var handle: (@MainActor (String, PaidPurchase) async -> Void)?
        func originalAppVersion() async -> String? { "10" }
        func read(_ productID: String) async -> PaidAccess.ProductRead { reads[productID].map { .transaction($0) } ?? .noSignal }
        func firstPurchaseDate(_ productID: String) async -> Date? { reads[productID]?.purchaseDate }
        func displayPrice(_ productID: String) async -> String? { "₩14,000" }
        /// Runs inside `purchase` before it returns, such as an approval that `Transaction.updates` delivers meanwhile.
        var duringPurchase: (@MainActor () async -> Void)?
        func purchase(_ productID: String) async throws -> PaidPurchaseOutcome {
            await duringPurchase?()
            if let purchaseResult { return try purchaseResult.get() }
            let purchase = PaidPurchase(purchaseDate: Date())
            reads[productID] = purchase
            return .purchased(purchase)
        }
        func sync() async throws { reads.merge(syncAdds) { $1 } }
        func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never> { self.handle = handle; return Task {} }
        func approve(_ productID: String) async {
            let purchase = PaidPurchase(purchaseDate: Date())
            reads[productID] = purchase
            await handle?(productID, purchase)
        }
    }
    private struct TestFailure: Error {}
    /// A model whose gate reads a real `PaidAccessStore`: a person who downloaded the paid build and bought nothing, with a 30-minute focus length.
    private func paywallModel() async -> (FocusModel, PaidAccessStore, PaywallStoreKit, ModelTestShield) {
        let shield = ModelTestShield(), kit = PaywallStoreKit()
        let store = PaidAccessStore(configuration: PaidAccessConfiguration(enabled: true, firstPaidBuild: 3), cache: nil, kit: kit)
        store.start()
        await store.refresh()
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.settings.lengthMinutes = 30
        services.paidAccess = { store.state }
        let model = FocusModel(services: services, history: ModelTestHistory(acknowledge: engine.acknowledgeTerminal))
        model.completeOnboarding(); model.refresh()
        XCTAssertEqual(store.state, .locked)
        return (model, store, kit, shield)
    }
    /// What the paywall does with one result of its own action: the sheet's decision (`PaywallOutcome`) and the callbacks that `FocusView` passes it.
    /// The auto-close of the sheet runs in the UI tests (`testApprovalWhileThePaywallIsOpenClosesItAndStartsNothing`, `testPaywallRestoreClosesItAndStartsNothing`).
    private func sheetResult(_ result: PaidActionResult, model: FocusModel, store: PaidAccessStore, request: PaywallRequest.ID? = nil) {
        guard let id = request ?? model.paywallRequest?.id else { return }
        switch PaywallOutcome(result, access: store.state) {
        case .continueStart: model.confirmPaywallStart(id)
        case .dropStart: model.dropPaywallStart(id)
        case .none: break
        }
    }
    private func assertNoSession(_ model: FocusModel, _ shield: ModelTestShield, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(model.current, message, file: file, line: line); XCTAssertFalse(shield.applied, message, file: file, line: line)
        XCTAssertNil(model.startRequestID, message, file: file, line: line); XCTAssertFalse(model.isStarting, message, file: file, line: line)
        XCTAssertNil(model.paywallRequest, message, file: file, line: line)
    }

    /// The required test of the paywall design: start entry, a pending purchase, "나중에", then the approval: access opens and no session starts.
    func testPendingPurchaseApprovedLaterOpensAccessOnly() async {
        let (model, store, kit, shield) = await paywallModel()
        XCTAssertNil(model.requestStart())
        XCTAssertEqual(model.paywallRequest?.holdsStart, true)
        kit.purchaseResult = .success(.pending)
        let result = await store.purchaseUnlock()
        XCTAssertEqual(result, .pending)
        sheetResult(result, model: model, store: store)
        XCTAssertEqual(model.paywallRequest?.holdsStart, false, "the start line goes away")
        model.dismissPaywall()
        await kit.approve(PaidAccess.unlockProductID)
        XCTAssertEqual(store.state, .granted)
        model.refresh(); model.tick()
        assertNoSession(model, shield)
        // The student taps the start action again.
        model.start()
        XCTAssertTrue(model.isActive)
    }
    /// An approval that arrives while the sheet is still open closes it, and the close starts nothing.
    func testApprovalWhileTheSheetIsOpenStartsNothing() async {
        let (model, store, kit, shield) = await paywallModel()
        model.requestStart()
        kit.purchaseResult = .success(.pending)
        sheetResult(await store.purchaseUnlock(), model: model, store: store)
        await kit.approve(PaidAccess.unlockProductID)
        XCTAssertEqual(store.state, .granted)
        XCTAssertTrue(PaywallOutcome.closesByItself(access: store.state, acting: false), "the approval closes the open sheet")
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// Start entry, trial confirmed: the close runs the start path once, with the student's length.
    func testConfirmedTrialContinuesTheStartOnce() async throws {
        let (model, store, _, _) = await paywallModel()
        model.requestStart()
        let result = await store.startTrial()
        XCTAssertEqual(result, .confirmed); XCTAssertEqual(store.state, .granted)
        sheetResult(result, model: model, store: store)
        model.dismissPaywall()
        XCTAssertNil(model.paywallRequest)
        let request = try XCTUnwrap(model.startRequestID)
        model.performPendingStart(request)
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(model.current?.length, 30 * 60)
        // A second close finds no request.
        let id = model.current?.id
        model.dismissPaywall()
        XCTAssertEqual(model.current?.id, id); XCTAssertNil(model.startRequestID)
    }
    /// A trial transaction that already ended, while an approved purchase opens access meanwhile, does not confirm the sheet's action,
    /// so the close starts nothing although access reads `granted`.
    func testEndedTrialTransactionDoesNotConfirmAccessThatAnotherTransactionOpened() async {
        let (model, store, kit, shield) = await paywallModel()
        model.requestStart()
        kit.purchaseResult = .success(.purchased(PaidPurchase(purchaseDate: Date().addingTimeInterval(-4 * 24 * 3600))))
        kit.duringPurchase = { await kit.approve(PaidAccess.unlockProductID) }
        let result = await store.startTrial()
        XCTAssertEqual(result, .notGranted); XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(PaywallOutcome(result, access: store.state), .dropStart)
        sheetResult(result, model: model, store: store)
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// Start entry, purchase confirmed: one session starts.
    func testConfirmedPurchaseContinuesTheStart() async throws {
        let (model, store, _, _) = await paywallModel()
        model.requestStart()
        sheetResult(await store.purchaseUnlock(), model: model, store: store)
        model.dismissPaywall()
        model.performPendingStart(try XCTUnwrap(model.startRequestID))
        XCTAssertTrue(model.isActive)
    }
    /// "나중에" or a swipe, a cancel and a failure start nothing; after a cancel or a failure, a later success in the same sheet starts nothing either.
    func testCloseCancelAndFailureStartNothing() async {
        for outcome in ["close", "cancel", "failure"] {
            let (model, store, kit, shield) = await paywallModel()
            model.requestStart()
            if outcome != "close" {
                kit.purchaseResult = outcome == "cancel" ? .success(.cancelled) : .failure(TestFailure())
                let result = await store.purchaseUnlock()
                XCTAssertEqual(result, outcome == "cancel" ? .cancelled : .failed, outcome)
                sheetResult(result, model: model, store: store)
                kit.purchaseResult = nil
                sheetResult(await store.startTrial(), model: model, store: store)
                XCTAssertEqual(store.state, .granted, outcome)
                XCTAssertEqual(model.paywallRequest?.confirmed, false, outcome)
            }
            model.dismissPaywall()
            assertNoSession(model, shield, outcome)
        }
    }
    /// Start entry, restore: access opens, the sheet closes, and no session starts.
    func testRestoreOpensAccessAndStartsNothing() async {
        let (model, store, kit, shield) = await paywallModel()
        model.requestStart()
        kit.syncAdds[PaidAccess.unlockProductID] = PaidPurchase(purchaseDate: Date())
        await store.restore()
        XCTAssertEqual(store.state, .granted)
        XCTAssertTrue(PaywallOutcome.closesByItself(access: store.state, acting: false), "the restore closes the sheet when it ends")
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// A confirmation while access does not read `granted` never runs the start path, which would open the paywall again.
    func testConfirmationWithoutAccessStartsNothing() async throws {
        let (model, _, _, shield) = await paywallModel()
        model.requestStart()
        model.confirmPaywallStart(try XCTUnwrap(model.paywallRequest?.id))
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// "나중에" drops the start request before the close, so a trial that the sheet confirms during the close animation starts nothing.
    func testConfirmationDuringTheLaterCloseStartsNothing() async throws {
        let (model, store, _, shield) = await paywallModel()
        model.requestStart()
        model.dropPaywallStart(try XCTUnwrap(model.paywallRequest?.id))
        sheetResult(await store.startTrial(), model: model, store: store)
        XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(model.paywallRequest?.confirmed, false)
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// Leaving the foreground with the paywall open drops its start: a trial confirmed after the return opens access only.
    func testBackgroundDropsThePaywallStart() async throws {
        let (model, store, _, shield) = await paywallModel()
        model.requestStart()
        let id = try XCTUnwrap(model.paywallRequest?.id)
        model.sceneDidLeaveForeground()
        XCTAssertEqual(model.paywallRequest?.id, id, "the sheet stays open")
        XCTAssertEqual(model.paywallRequest?.holdsStart, false, "the start line goes away")
        sheetResult(await store.startTrial(), model: model, store: store)
        XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(model.paywallRequest?.confirmed, false)
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// A result of a closed sheet confirms or drops nothing in the request that a later start tap made.
    func testLateResultOfAClosedSheetDoesNotReachALaterRequest() async throws {
        let (model, store, _, shield) = await paywallModel()
        model.requestStart()
        let first = try XCTUnwrap(model.paywallRequest?.id)
        model.dismissPaywall()
        model.requestStart()
        let second = try XCTUnwrap(model.paywallRequest?.id)
        XCTAssertNotEqual(first, second)
        sheetResult(.failed, model: model, store: store, request: first)
        XCTAssertEqual(model.paywallRequest?.holdsStart, true, "a late failure of the first sheet keeps the second request")
        sheetResult(await store.startTrial(), model: model, store: store, request: first)
        XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(model.paywallRequest?.confirmed, false, "a late confirmation of the first sheet does not confirm the second request")
        model.dismissPaywall()
        assertNoSession(model, shield)
    }
    /// The sheet's two decisions: only a confirmed result with access `granted` continues the start, and open access closes the sheet
    /// only while none of its own actions runs.
    func testPaywallOutcome() {
        XCTAssertEqual(PaywallOutcome(.confirmed, access: .granted), .continueStart)
        XCTAssertEqual(PaywallOutcome(.confirmed, access: .locked), .dropStart)
        XCTAssertEqual(PaywallOutcome(.confirmed, access: .unknown), .dropStart)
        for result in [PaidActionResult.notGranted, .pending, .cancelled, .failed] { XCTAssertEqual(PaywallOutcome(result, access: .granted), .dropStart, "\(result)") }
        XCTAssertEqual(PaywallOutcome(.busy, access: .locked), .none)
        XCTAssertTrue(PaywallOutcome.closesByItself(access: .granted, acting: false))
        XCTAssertFalse(PaywallOutcome.closesByItself(access: .granted, acting: true))
        XCTAssertFalse(PaywallOutcome.closesByItself(access: .locked, acting: false))
        XCTAssertFalse(PaywallOutcome.closesByItself(access: .unknown, acting: false))
    }
}
