import Foundation
public enum HIDParser {
    public static func parse(_ text: String) throws -> [[KeyMapping]] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw invalid() }
        if trimmed.hasPrefix("(") { return [try parseValue(trimmed)] }
        let regex = try NSRegularExpression(pattern: #"(?m)^[\t ]*(?:0x)?[0-9a-fA-F]+[\t ]+UserKeyMapping[\t ]+"#)
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        let headerEnd = matches.first?.range.location ?? ns.length
        let header = ns.substring(to: headerEnd).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard header == "RegistryID Key Value" else { throw invalid() }
        return try matches.enumerated().map { i, match in
            let start = NSMaxRange(match.range)
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            return try parseValue(ns.substring(with: NSRange(location: start, length: end - start)))
        }
    }
    private static func parseValue(_ value: String) throws -> [KeyMapping] {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "(null)" { return [] }
        guard let data = value.data(using: .utf8),
              let array = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else { throw invalid() }
        let result = try array.map { item -> KeyMapping in
            guard Set(item.keys) == ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"],
                  let source = number(item["HIDKeyboardModifierMappingSrc"]),
                  let destination = number(item["HIDKeyboardModifierMappingDst"]) else { throw invalid() }
            return KeyMapping(source, destination)
        }
        try MappingPolicy.validate(result)
        return result
    }
    private static func number(_ value: Any?) -> UInt64? {
        if let str = value as? String {
            return str.lowercased().hasPrefix("0x") ? UInt64(str.dropFirst(2), radix: 16) : UInt64(str)
        }
        if let n = value as? NSNumber, n.int64Value >= 0 { return n.uint64Value }
        return nil
    }
    private static func invalid() -> HelperError {
        HelperError("macOS의 키 설정 응답을 읽을 수 없어 변경하지 않았습니다. 이 macOS 버전은 추가 확인이 필요합니다.")
    }
}
