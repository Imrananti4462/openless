import Foundation

/// 火山引擎大模型流式 ASR 二进制帧编解码。
///
/// 帧结构通常为：4 字节 header + 可选 sequence + 4 字节大端 payload size + payload。
/// 为了避免运行时依赖 gzip 实现，这里显式使用 no compression；官方协议允许客户端选择
/// no compression，服务端会沿用客户端声明的压缩方式。
enum VolcengineFrame {

    enum MessageType: UInt8 {
        case fullClientRequest = 0b0001
        case audioOnlyRequest = 0b0010
        case fullServerResponse = 0b1001
        case errorMessage = 0b1111
    }

    enum Flags: UInt8 {
        case none = 0b0000
        case positiveSequence = 0b0001
        case lastPacket = 0b0010
        case negativeSequence = 0b0011
    }

    enum Serialization: UInt8 {
        case none = 0b0000
        case json = 0b0001
    }

    enum CompressionMethod: UInt8 {
        case none = 0b0000
    }

    static func build(
        messageType: MessageType,
        flags: Flags,
        serialization: Serialization,
        payload: Data,
        sequence: Int32? = nil
    ) -> Data {
        var frame = Data()
        frame.append(0x11)
        frame.append((messageType.rawValue << 4) | flags.rawValue)
        frame.append((serialization.rawValue << 4) | CompressionMethod.none.rawValue)
        frame.append(0x00)

        // positiveSequence / negativeSequence 必须带 4 字节大端 seq；其它 flag 不带。
        if let sequence, flags == .positiveSequence || flags == .negativeSequence {
            var seq = UInt32(bitPattern: sequence).bigEndian
            withUnsafeBytes(of: &seq) { frame.append(contentsOf: $0) }
        }

        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    static func parse(_ data: Data) -> ParsedFrame? {
        guard data.count >= 8 else { return nil }

        let headerSize = Int(data[0] & 0x0F) * 4
        guard headerSize >= 4, data.count >= headerSize + 4 else { return nil }

        let messageTypeRaw = (data[1] >> 4) & 0x0F
        let messageType = MessageType(rawValue: messageTypeRaw)
        let flagsRaw = data[1] & 0x0F
        let compression = data[2] & 0x0F
        guard compression == CompressionMethod.none.rawValue else { return nil }

        var offset = headerSize
        var sequence: Int32?

        if hasSequence(flagsRaw) {
            guard let value = readInt32(data, at: offset) else { return nil }
            sequence = value
            offset += 4
        }

        if messageType == .errorMessage {
            guard let code = readUInt32(data, at: offset),
                  let messageSize = readUInt32(data, at: offset + 4) else {
                return nil
            }
            offset += 8
            guard data.count >= offset + Int(messageSize) else { return nil }
            let payload = data.subdata(in: offset..<(offset + Int(messageSize)))
            return ParsedFrame(messageType: messageType, flags: flagsRaw, sequence: sequence, errorCode: code, payload: payload)
        }

        guard let payloadSize = readUInt32(data, at: offset) else { return nil }
        offset += 4
        guard data.count >= offset + Int(payloadSize) else { return nil }
        let payload = data.subdata(in: offset..<(offset + Int(payloadSize)))
        return ParsedFrame(messageType: messageType, flags: flagsRaw, sequence: sequence, errorCode: nil, payload: payload)
    }

    struct ParsedFrame {
        let messageType: MessageType?
        let flags: UInt8
        let sequence: Int32?
        let errorCode: UInt32?
        let payload: Data

        var isFinal: Bool {
            flags == Flags.lastPacket.rawValue
                || flags == Flags.negativeSequence.rawValue
                || (sequence ?? 0) < 0
        }
    }

    private static func hasSequence(_ flags: UInt8) -> Bool {
        flags == Flags.positiveSequence.rawValue || flags == Flags.negativeSequence.rawValue
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        var value: UInt32 = 0
        for byte in data[offset..<(offset + 4)] {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int32? {
        guard let unsigned = readUInt32(data, at: offset) else { return nil }
        return Int32(bitPattern: unsigned)
    }
}
