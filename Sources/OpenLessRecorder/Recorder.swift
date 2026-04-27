import AVFoundation
import Foundation
import OpenLessCore

public enum RecorderError: Error, Sendable {
    case permissionDenied
    case engineFailed(String)
}

public final class Recorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var consumer: AudioConsumer?
    private let lock = NSLock()
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var logger: (@Sendable (String) -> Void)?
    private var bufferCount: Int = 0
    private var peakInputRMS: Double = 0
    private var peakOutputRMS: Double = 0

    private let targetSampleRate: Double = 16_000

    public init() {}

    public func start(
        consumer: AudioConsumer,
        levelHandler: @escaping @Sendable (Float) -> Void,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws {
        if !MicrophonePermission.isGranted() {
            let granted = await MicrophonePermission.request()
            if !granted { throw RecorderError.permissionDenied }
        }

        setConsumer(consumer, levelHandler: levelHandler, logger: logger)
        bufferCount = 0
        peakInputRMS = 0
        peakOutputRMS = 0

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        logger?("[recorder] inputFormat sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount) common=\(inputFormat.commonFormat.rawValue)")

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.engineFailed("create output format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
            throw RecorderError.engineFailed("create converter")
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, outFormat: outFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw RecorderError.engineFailed(error.localizedDescription)
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let count = bufferCount
        let pkIn = peakInputRMS
        let pkOut = peakOutputRMS
        let snapshotLogger = logger
        lock.unlock()
        snapshotLogger?("[recorder] session 总结：\(count) buffer，peak inRMS=\(String(format: "%.5f", pkIn)) outRMS=\(String(format: "%.5f", pkOut))")
        setConsumer(nil, levelHandler: nil)
    }

    private func setConsumer(
        _ consumer: AudioConsumer?,
        levelHandler: (@Sendable (Float) -> Void)?,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        lock.lock()
        self.consumer = consumer
        self.levelHandler = levelHandler
        self.logger = logger
        lock.unlock()
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outFormat: AVAudioFormat
    ) {
        // 留一些 headroom，避免下采样滤波器对边界帧计算时 capacity 不足。
        let outFrameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate) + 64
        )
        guard outFrameCapacity > 0 else { return }
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrameCapacity) else { return }

        // 关键：closure 喂完一次 buffer 后用 .noDataNow（不是 .endOfStream）。
        // .endOfStream 会让 AVAudioConverter flush 内部 resampler 进入"流已结束"状态——
        // 之前日志显示 buf#1 outLen=1600 正常，buf#2 起永远 outLen=0 就是这个原因。
        // .noDataNow 告诉 converter "暂时没数据但流没结束"，跨 buffer 保留 resampler 状态。
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return }
        guard let int16Pointer = outBuffer.int16ChannelData?[0] else { return }

        let frameCount = Int(outBuffer.frameLength)
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Pointer, count: byteCount)

        // 计算音量 (RMS) 给 UI
        var sumSquares: Double = 0
        for i in 0..<frameCount {
            let sample = Double(int16Pointer[i]) / 32768.0
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Double(max(frameCount, 1)))
        let normalized = Float(min(1.0, rms * 4))

        // 节流诊断：每 10 个 buffer 打一行；峰值在每 buffer 都更新。
        let inputRMS = computeInputRMS(buffer)
        lock.lock()
        bufferCount += 1
        let count = bufferCount
        if inputRMS > peakInputRMS { peakInputRMS = inputRMS }
        if rms > peakOutputRMS { peakOutputRMS = rms }
        let snapshotLogger = logger
        lock.unlock()
        if count == 1 || count % 10 == 0 {
            snapshotLogger?("[recorder] buf#\(count) inLen=\(buffer.frameLength) inSR=\(Int(buffer.format.sampleRate)) inRMS=\(String(format: "%.5f", inputRMS)) outLen=\(frameCount) outRMS=\(String(format: "%.5f", rms))")
        }

        lock.lock()
        let snapshotConsumer = consumer
        let snapshotLevel = levelHandler
        lock.unlock()
        snapshotConsumer?.consume(pcmChunk: data)
        snapshotLevel?(normalized)
    }

    /// 仅用于诊断：在 convert 前直接算输入 buffer 的 RMS，确定静音是 mic 端还是 converter 端引入的。
    private func computeInputRMS(_ buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        if let floatPtr = buffer.floatChannelData?[0] {
            var sum: Double = 0
            for i in 0..<frameLength {
                let s = Double(floatPtr[i])
                sum += s * s
            }
            return sqrt(sum / Double(frameLength))
        }
        if let intPtr = buffer.int16ChannelData?[0] {
            var sum: Double = 0
            for i in 0..<frameLength {
                let s = Double(intPtr[i]) / 32768.0
                sum += s * s
            }
            return sqrt(sum / Double(frameLength))
        }
        return -1 // 表示未知格式
    }
}
