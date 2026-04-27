import SwiftUI
import OpenLessHotkey
import OpenLessRecorder

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var accessibilityGranted = AccessibilityPermission.isGranted()
    @State private var microphoneGranted = MicrophonePermission.isGranted()
    @State private var pollingTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("欢迎使用 OpenLess")
                    .font(.system(size: 22, weight: .semibold))
                Text("还差两个权限就可以开始用语音输入。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            permissionRow(
                index: 1,
                title: "辅助功能",
                detail: "用于全局快捷键和把整理后的文字写回当前输入框。",
                granted: accessibilityGranted,
                action: requestAccessibility
            )

            permissionRow(
                index: 2,
                title: "麦克风",
                detail: "用于录音转写。音频默认不保存。",
                granted: microphoneGranted,
                action: requestMicrophone
            )

            Spacer()

            HStack {
                Spacer()
                if accessibilityGranted && microphoneGranted {
                    Button(action: complete) {
                        Text("完成并重启 OpenLess")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("两项都打勾后再继续")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 480, height: 360)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private func permissionRow(
        index: Int,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "\(index).circle")
                .font(.system(size: 20))
                .foregroundStyle(granted ? Color.green : Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: action) {
                Text(granted ? "已授权" : "授权")
                    .frame(minWidth: 64)
            }
            .controlSize(.regular)
            .disabled(granted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - 动作

    private func requestAccessibility() {
        // AXIsProcessTrustedWithOptions 首次会开「系统设置 → 隐私与安全 → 辅助功能」
        AccessibilityPermission.request()
    }

    private func requestMicrophone() {
        Task {
            let granted = await MicrophonePermission.request()
            await MainActor.run { microphoneGranted = granted }
        }
    }

    /// 开「系统设置 → 辅助功能」需要用户手动勾，没法回调；这里轮询 1s 一次刷新状态。
    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let ax = AccessibilityPermission.isGranted()
            let mic = MicrophonePermission.isGranted()
            DispatchQueue.main.async {
                if ax != accessibilityGranted { accessibilityGranted = ax }
                if mic != microphoneGranted { microphoneGranted = mic }
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func complete() {
        stopPolling()
        onComplete()
    }
}
