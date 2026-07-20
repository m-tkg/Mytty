import Foundation

public enum RemoteFrameError: Error, Equatable, Sendable {
    case frameTooLarge
}

/// Wire framing for the remote control connection. Frames may carry either
/// plaintext JSON or AES-GCM ciphertext (see `RemoteSecureChannel`), so a
/// length prefix is used instead of a delimiter byte that ciphertext could
/// legitimately contain.
public enum RemoteFrameCodec {
    public static let maximumFrameSize = 1 * 1024 * 1024

    public static func encode(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var data = Data([
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ])
        data.append(payload)
        return data
    }
}

/// Accumulates raw bytes from a stream connection and splits them into
/// length-prefixed frames as they arrive.
public struct RemoteFrameReader {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while true {
            guard buffer.count >= 4 else { break }
            let prefix = buffer.prefix(4)
            let length = prefix.reduce(0) { accumulator, byte in
                (accumulator << 8) | Int(byte)
            }
            guard length <= RemoteFrameCodec.maximumFrameSize else {
                throw RemoteFrameError.frameTooLarge
            }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex.advanced(by: 4)
            let end = start.advanced(by: length)
            frames.append(Data(buffer[start..<end]))
            buffer.removeSubrange(buffer.startIndex..<end)
        }
        return frames
    }
}
