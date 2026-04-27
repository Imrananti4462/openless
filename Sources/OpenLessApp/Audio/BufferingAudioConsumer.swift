import Foundation
import OpenLessCore

final class BufferingAudioConsumer: AudioConsumer, @unchecked Sendable {
    private let lock = NSLock()
    private let maxBufferedBytes: Int
    private var target: AudioConsumer?
    private var bufferedChunks: [Data] = []
    private var bufferedByteCount = 0

    init(maxBufferedBytes: Int = 320_000) {
        self.maxBufferedBytes = maxBufferedBytes
    }

    func consume(pcmChunk: Data) {
        lock.lock()
        if let target {
            lock.unlock()
            target.consume(pcmChunk: pcmChunk)
            return
        }

        bufferedChunks.append(pcmChunk)
        bufferedByteCount += pcmChunk.count

        while bufferedByteCount > maxBufferedBytes, let first = bufferedChunks.first {
            bufferedByteCount -= first.count
            bufferedChunks.removeFirst()
        }
        lock.unlock()
    }

    func attach(_ target: AudioConsumer) {
        lock.lock()
        self.target = target
        let pending = bufferedChunks
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedByteCount = 0
        lock.unlock()

        for chunk in pending {
            target.consume(pcmChunk: chunk)
        }
    }

    func clear() {
        lock.lock()
        target = nil
        bufferedChunks.removeAll(keepingCapacity: false)
        bufferedByteCount = 0
        lock.unlock()
    }
}
