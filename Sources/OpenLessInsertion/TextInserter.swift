import AppKit
import ApplicationServices
import OpenLessCore

public enum InsertResult: Sendable {
    case inserted
    case copiedFallback(reason: String)
}

public final class TextInserter: @unchecked Sendable {
    public init() {}

    @MainActor
    public func insert(_ text: String) async -> InsertResult {
        guard !text.isEmpty else { return .copiedFallback(reason: "empty text") }

        // 不论后续走 AX 还是模拟粘贴，先把剪贴板就绪：
        // - AX 声称成功但实际没插入（Electron / Web textarea 常见）时，用户能 Cmd+V 兜底
        // - 模拟粘贴本身就需要剪贴板里有内容
        copyToClipboard(text)

        // 策略 1：通过 AX 找到当前 focused element 直接写文本（macOS 原生输入框成功率高）
        if let result = tryAXInsert(text) {
            return result
        }

        // 策略 2：模拟 Cmd+V（覆盖 Electron/网页/IM 等没实现 AX 写入的场景）
        if simulatePaste() {
            return .inserted
        }

        return .copiedFallback(reason: "AX + 模拟粘贴均失败；文本已复制，请 ⌘V 手动粘贴")
    }

    // MARK: - AX

    private func tryAXInsert(_ text: String) -> InsertResult? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let element = focused else { return nil }
        // swiftlint:disable:next force_cast
        let elem = element as! AXUIElement

        var roleObj: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleObj)
        let role = roleObj as? String ?? ""

        // 仅在 textfield / textarea 上尝试 AXValue 写入
        if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String {
            // 先尝试在 selection 处插入
            var rangeObj: AnyObject?
            let rangeErr = AXUIElementCopyAttributeValue(elem, kAXSelectedTextRangeAttribute as CFString, &rangeObj)
            if rangeErr == .success, let _ = rangeObj {
                let setErr = AXUIElementSetAttributeValue(elem, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
                if setErr == .success {
                    return .inserted
                }
            }
            // 否则覆盖整个 value
            var valueObj: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valueObj)
            let existing = valueObj as? String ?? ""
            let combined = existing + text
            let setErr = AXUIElementSetAttributeValue(elem, kAXValueAttribute as CFString, combined as CFTypeRef)
            if setErr == .success {
                return .inserted
            }
        }
        return nil
    }

    // MARK: - Clipboard + simulated paste

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func simulatePaste() -> Bool {
        // 用 .hidSystemState + .cghidEventTap：让 Cmd+V 看起来像真实硬件键盘，
        // 不容易被 Electron / 网页输入框忽略；之前用 .combinedSessionState +
        // .cgAnnotatedSessionEventTap 在某些 app 上不触发粘贴。
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), // V key
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
