import Foundation

public protocol AudioConsumer: AnyObject, Sendable {
    /// 16 kHz / 16-bit signed PCM / mono；建议 100-200 ms 一包
    func consume(pcmChunk: Data)
}
