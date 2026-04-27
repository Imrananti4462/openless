import Foundation

public enum CapsuleState: Sendable, Equatable {
    case hidden
    case listening
    case processing
    case inserted
    case cancelled
    case copied
    case error(String)
    /// 插入/复制成功但有需要告诉用户的非阻塞偏离（如润色被跳过、润色失败回退原文）。
    case warning(String)
}
