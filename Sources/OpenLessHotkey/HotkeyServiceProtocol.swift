import Foundation
import OpenLessCore

@MainActor
public protocol HotkeyServiceProtocol: AnyObject {
    var events: AsyncStream<HotkeyEvent> { get }
    var isRunning: Bool { get }
    func start(binding: HotkeyBinding) throws
    func stop()
    func updateBinding(_ binding: HotkeyBinding)
}
