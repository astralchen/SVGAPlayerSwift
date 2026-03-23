import Foundation
import ZIPFoundation
import zlib

enum SVGADecompressorError: Error {
    case zlibInflateFailed
}

enum SVGADecompressor {
    static func isZIP(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B // "PK"
    }

    static func isMP3(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 // "ID3"
    }

    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        let fullLength = data.count
        let halfLength = fullLength / 2
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
                let offset = Int(strm.total_out)
                let available = uInt(decompressed.count) - uInt(offset)
                let status = decompressed.withUnsafeMutableBytes { outPtr in
                    strm.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress!.advanced(by: offset)
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

    static func unzip(_ data: Data, to url: URL) throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".svga")
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: tmpURL, to: url)
    }
}
