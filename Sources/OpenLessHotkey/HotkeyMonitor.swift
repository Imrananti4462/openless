import AppKit
import CoreGraphics
import OpenLessCore

@MainActor
public final class HotkeyMonitor: HotkeyServiceProtocol {
    public let events: AsyncStream<HotkeyEvent>
    public private(set) var isRunning = false

    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private var binding: HotkeyBinding = .default
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var triggerHeld = false
    /// 边沿事件：触发键按下时发 .pressed，松开时发 .released。
    /// toggle / hold 的解释由协调器侧（DictationCoordinator）按用户偏好做。

    public init() {
        var captured: AsyncStream<HotkeyEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    public func start(binding: HotkeyBinding) throws {
        guard !isRunning else { throw HotkeyError.alreadyRunning }
        guard AccessibilityPermission.isGranted() else {
            throw HotkeyError.accessibilityNotGranted
        }

        self.binding = binding

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: selfPtr
        ) else {
            throw HotkeyError.eventTapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        triggerHeld = false
        isRunning = false
    }

    public func updateBinding(_ binding: HotkeyBinding) {
        self.binding = binding
        triggerHeld = false
    }

    fileprivate func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let triggerKeyCode = expectedKeyCode(for: binding.trigger)

        guard keyCode == triggerKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let triggerMask = expectedFlagMask(for: binding.trigger)
        let triggerActive = event.flags.contains(triggerMask)

        if triggerActive && !triggerHeld {
            triggerHeld = true
            continuation.yield(.pressed)
        } else if !triggerActive && triggerHeld {
            triggerHeld = false
            continuation.yield(.released)
        }

        // fn 默认拦截，规避系统 Globe 行为
        if shouldInterceptTrigger() {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let escapeKeyCode: Int64 = 53
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == escapeKeyCode {
            continuation.yield(.cancelled)
        }
        return Unmanaged.passUnretained(event)
    }

    private func shouldInterceptTrigger() -> Bool {
        binding.trigger == .fn
    }

    private func expectedKeyCode(for trigger: HotkeyBinding.Trigger) -> Int {
        switch trigger {
        case .leftControl: return 59
        case .rightCommand: return 54
        case .leftOption: return 58
        case .rightOption: return 61
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    private func expectedFlagMask(for trigger: HotkeyBinding.Trigger) -> CGEventFlags {
        switch trigger {
        case .leftControl, .rightControl: return .maskControl
        case .rightCommand: return .maskCommand
        case .leftOption, .rightOption: return .maskAlternate
        case .fn: return .maskSecondaryFn
        }
    }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.reenableTap()
        }
        return Unmanaged.passUnretained(event)
    }

    return MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
}
