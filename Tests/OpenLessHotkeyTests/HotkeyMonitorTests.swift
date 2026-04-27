import XCTest
@testable import OpenLessHotkey

@MainActor
final class HotkeyMonitorTests: XCTestCase {
    func test_doubleStartThrowsAlreadyRunning() throws {
        let monitor = HotkeyMonitor()

        guard AccessibilityPermission.isGranted() else {
            throw XCTSkip("需要辅助功能权限才能运行此测试")
        }

        try monitor.start(binding: .default)
        defer { monitor.stop() }

        XCTAssertThrowsError(try monitor.start(binding: .default)) { error in
            XCTAssertEqual(error as? HotkeyError, .alreadyRunning)
        }
    }

    func test_stopBeforeStartIsNoOp() {
        let monitor = HotkeyMonitor()
        XCTAssertFalse(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func test_isRunningReflectsLifecycle() throws {
        let monitor = HotkeyMonitor()

        guard AccessibilityPermission.isGranted() else {
            throw XCTSkip("需要辅助功能权限才能运行此测试")
        }

        XCTAssertFalse(monitor.isRunning)
        try monitor.start(binding: .default)
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func test_updateBindingDoesNotCrashWhenNotRunning() {
        let monitor = HotkeyMonitor()
        monitor.updateBinding(HotkeyBinding(trigger: .fn))
    }
}
