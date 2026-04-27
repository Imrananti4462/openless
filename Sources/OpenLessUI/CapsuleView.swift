import SwiftUI

public struct CapsuleView: View {
    private let state: CapsuleState
    private let level: Float
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(
        state: CapsuleState,
        level: Float,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {}
    ) {
        self.state = state
        self.level = level
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        HStack(spacing: 8) {
            cancelButton
            centerView
            confirmButton
        }
        .padding(.horizontal, 10)
        .frame(width: 152, height: 32)
        .openLessGlass()
        .modifier(LegacyCapsuleChrome(state: state))
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 14)
                .foregroundStyle(state == .cancelled ? Color.red : Color.gray.opacity(0.85))
                .opacity(state == .hidden ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isControlEnabled)
        .help("取消")
    }

    @ViewBuilder
    private var confirmButton: some View {
        Button(action: onConfirm) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 14)
                .foregroundStyle(state == .inserted ? Color.green : Color.white)
                .opacity(state == .hidden ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isControlEnabled)
        .help("结束并整理")
    }

    @ViewBuilder
    private var centerView: some View {
        switch state {
        case .listening:
            AudioBars(level: level).frame(width: centerWidth)
        case .processing:
            HStack(spacing: 6) {
                ProgressDots()
                Text("正在思考中")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: centerWidth)
        case .inserted:
            statusText("已插入", color: .secondary)
        case .cancelled:
            statusText("已取消", color: .secondary)
        case .copied:
            statusText("已复制 ⌘V", color: .secondary)
        case .error(let msg):
            statusText(msg, color: .red)
        case .hidden:
            EmptyView()
        }
    }

    private var centerWidth: CGFloat { 82 }

    private var isControlEnabled: Bool {
        state == .listening
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: centerWidth)
    }
}

/// macOS 15 上保留旧的描边和投影；macOS 26 上完全交给 Liquid Glass。
private struct LegacyCapsuleChrome: ViewModifier {
    let state: CapsuleState

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
    }
}

private struct AudioBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: level)
            }
        }
        .frame(width: 35)
    }

    private func barHeight(index: Int) -> CGFloat {
        // 中间高、两边低；level=0 时仍有 4pt 基线，避免视觉静止
        let base: CGFloat = 4
        let maxHeight: CGFloat = 18
        let voice = CGFloat(min(1, max(0, level)))
        let envelope: [CGFloat] = [0.55, 0.85, 1.0, 0.85, 0.55]
        return base + (maxHeight - base) * voice * envelope[index]
    }
}

private struct ProgressDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .opacity(dotOpacity(index: i))
            }
        }
        .frame(width: 20)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func dotOpacity(index: Int) -> Double {
        let p = (phase + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
        return 0.3 + abs(sin(p * .pi)) * 0.7
    }
}
