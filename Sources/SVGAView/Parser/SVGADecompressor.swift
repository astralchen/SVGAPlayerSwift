import Foundation
import ZIPFoundation
import zlib

/// SVGA 解压过程中产生的错误。
enum SVGADecompressorError: Error {
    /// zlib inflate 失败。
    case zlibInflateFailed
    /// 解压后的数据超过允许的大小限制。
    case decompressedSizeExceeded
}

/// 提供 SVGA 压缩数据检测和解压能力的工具类型。
enum SVGADecompressor {
    /// 允许解压出的最大数据大小。
    static let maxDecompressedSize = 100_000_000 // 100 MB

    /// 返回数据是否看起来是 ZIP 文件。
    ///
    /// - Parameter data: 要检测的数据。
    /// - Returns: 数据以 ZIP magic number 开头时返回 `true`。
    static func isZIP(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B // "PK"
    }

    /// 返回数据是否看起来是 MP3 文件。
    ///
    /// - Parameter data: 要检测的数据。
    /// - Returns: 数据以 ID3 magic number 开头时返回 `true`。
    static func isMP3(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 // "ID3"
    }

    /// 使用 zlib 解压原始 SVGA 数据。
    ///
    /// - Parameter data: zlib 压缩数据。
    /// - Returns: 解压后的数据。
    /// - Throws: 解压失败或输出超过大小限制时抛出错误。
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        let fullLength = data.count
        let halfLength = max(fullLength / 2, 1024)
        var decompressed = Data(count: fullLength + halfLength)
        var done = false

        try data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) throws in
            guard let inPtr = rawPtr.bindMemory(to: Bytef.self).baseAddress else {
                throw SVGADecompressorError.zlibInflateFailed
            }
            var strm = z_stream()
            strm.next_in = UnsafeMutablePointer(mutating: inPtr)
            strm.avail_in = uInt(data.count)
            strm.zalloc = nil
            strm.zfree = nil
            guard inflateInit_(&strm, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw SVGADecompressorError.zlibInflateFailed
            }
            defer { inflateEnd(&strm) }

            while !done {
                if Int(strm.total_out) >= decompressed.count {
                    decompressed.count += halfLength
                }
                guard decompressed.count <= maxDecompressedSize else {
                    throw SVGADecompressorError.decompressedSizeExceeded
                }
                let offset = Int(strm.total_out)
                let available = uInt(decompressed.count) - uInt(offset)
                let status: Int32 = try decompressed.withUnsafeMutableBytes { outPtr in
                    guard let base = outPtr.bindMemory(to: Bytef.self).baseAddress else {
                        throw SVGADecompressorError.zlibInflateFailed
                    }
                    strm.next_out = base.advanced(by: offset)
                    strm.avail_out = available
                    return zlib.inflate(&strm, Z_SYNC_FLUSH)
                }
                if status == Z_STREAM_END { done = true }
                else if status != Z_OK { throw SVGADecompressorError.zlibInflateFailed }
            }
            decompressed.count = Int(strm.total_out)
        }
        guard done else { throw SVGADecompressorError.zlibInflateFailed }
        return decompressed
    }

    /// 将 ZIP 格式的 SVGA 数据解压到指定目录。
    ///
    /// - Parameters:
    ///   - data: ZIP 文件数据。
    ///   - url: 输出目录 URL。
    /// - Throws: 写入、解压失败或输出超过大小限制时抛出错误。
    static func unzip(_ data: Data, to url: URL) throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".svga")
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let archive = try Archive(url: tmpURL, accessMode: .read)
        var totalSize: Int64 = 0
        for entry in archive {
            totalSize += Int64(entry.uncompressedSize)
            guard totalSize <= Int64(maxDecompressedSize) else {
                throw SVGADecompressorError.decompressedSizeExceeded
            }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: tmpURL, to: url)
    }
}
