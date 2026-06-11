import CoreGraphics
import Foundation

/// SVGA JSON object 的字典表示。
typealias SVGAJSONObject = [String: SVGAJSONValue]

/// 保留 JSON 原始类型信息的值类型。
///
/// `SVGAJSONValue` 用于解析 SVGA 1.x 的 `movie.spec`，让模型层可以在
/// 保持类型安全的同时按需读取 object、array、string、number 和 bool。
enum SVGAJSONValue: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// JSON object。
    case object(SVGAJSONObject)
    /// JSON array。
    case array([SVGAJSONValue])
    /// JSON string。
    case string(String)
    /// JSON number。
    case number(Double)
    /// JSON bool。
    case bool(Bool)
    /// JSON null。
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SVGAJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(SVGAJSONObject.self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                SVGAJSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    var debugDescription: String {
        description
    }
}

extension Dictionary where Key == String, Value == SVGAJSONValue {
    /// 返回指定 key 对应的 JSON object。
    func object(_ key: String) -> SVGAJSONObject? {
        guard case .object(let value) = self[key] else { return nil }
        return value
    }

    /// 返回指定 key 对应的 JSON object 数组。
    func objectArray(_ key: String) -> [SVGAJSONObject]? {
        guard case .array(let values) = self[key] else { return nil }
        let objects: [SVGAJSONObject] = values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
        return objects.count == values.count ? objects : nil
    }

    /// 返回指定 key 对应的 JSON object 数组；不存在或类型不匹配时返回空数组。
    func objects(_ key: String) -> [SVGAJSONObject] {
        objectArray(key) ?? []
    }

    /// 返回指定 key 对应的字符串。
    func string(_ key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }

    /// 返回指定 key 对应的数字。
    func number(_ key: String) -> Double? {
        guard case .number(let value) = self[key] else { return nil }
        return value
    }

    /// 返回指定 key 对应的布尔值。
    func bool(_ key: String) -> Bool? {
        guard case .bool(let value) = self[key] else { return nil }
        return value
    }

    /// 返回指定 key 对应的 `CGFloat` 值。
    ///
    /// - Parameters:
    ///   - key: 要读取的 key。
    ///   - defaultValue: key 不存在或类型不匹配时返回的默认值。
    func cgFloat(_ key: String, default defaultValue: CGFloat = 0) -> CGFloat {
        number(key).map { CGFloat($0) } ?? defaultValue
    }

    /// 返回指定 key 对应的数字数组。
    func numbers(_ key: String) -> [Double]? {
        guard case .array(let values) = self[key] else { return nil }
        let numbers: [Double] = values.compactMap { value in
            guard case .number(let number) = value else { return nil }
            return number
        }
        return numbers.count == values.count ? numbers : nil
    }

    /// 返回指定 key 对应的字符串字典。
    func stringMap(_ key: String) -> [String: String]? {
        guard case .object(let object) = self[key] else { return nil }
        let strings = object.reduce(into: [String: String]()) { result, element in
            guard case .string(let value) = element.value else { return }
            result[element.key] = value
        }
        return strings.count == object.count ? strings : nil
    }
}
