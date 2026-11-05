import XCTest
import SwiftData
import Darwin

/// Measures the unchanged main-actor start path, with real control files and in-memory history.
/// Authorization, monitoring, selection and shields are synthetic; these are not device SDK timings.
@MainActor final class StartLatencyTests: XCTestCase {
    func testMeasureSynchronousStartWithoutContention() throws {
        try measureStarts(label: "no-contention", count: 30, holdLock: false)
    }

    func testMeasureSynchronousStartWithLockTimeout() throws {
        try measureStarts(label: "lock-timeout", count: 5, holdLock: true)
    }

    private func measureStarts(label: String, count: Int, holdLock: Bool) throws {
        var samples: [Double] = []
        for _ in 0..<count {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StartLatency-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = SharedControlStore(directory: directory)
            let shield = ModelTestShield()
            let engine = SessionControl(store: store, monitoring: ModelTestMonitoring(), shield: shield,
                                        breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
            let suite = "StartLatency-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine,
                                         applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
            services.settings = FocusSettings(defaults: defaults)
            let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            let model = FocusModel(services: services, context: ModelContext(container))
            model.completeOnboarding()
            XCTAssertTrue(model.canStart)
            let fd = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw ControlIssue.io }
            defer { close(fd) }
            if holdLock { XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0) }
            let started = ProcessInfo.processInfo.systemUptime
            model.start()
            samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            if holdLock {
                XCTAssertEqual(flock(fd, LOCK_UN), 0)
                XCTAssertNil(model.current)
                XCTAssertNotNil(model.errorMessage)
                XCTAssertFalse(shield.applied)
            } else {
                XCTAssertTrue(model.isActive)
                XCTAssertNil(model.errorMessage)
                XCTAssertTrue(shield.applied)
            }
        }
        let sorted = samples.sorted()
        let p50 = sorted[Int(ceil(Double(count) * 0.50)) - 1]
        let p95 = sorted[Int(ceil(Double(count) * 0.95)) - 1]
        let report = "START_LATENCY \(label) n=\(count) p50_ms=\(p50) p95_ms=\(p95) max_ms=\(sorted.last!) samples_ms=\(samples)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Start latency: \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
