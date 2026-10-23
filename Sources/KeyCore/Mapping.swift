import Foundation
public struct KeyMapping: Codable, Equatable {
    public let source: UInt64
    public let destination: UInt64
    public init(_ source: UInt64, _ destination: UInt64) { self.source = source; self.destination = destination }
    enum CodingKeys: String, CodingKey { case source = "HIDKeyboardModifierMappingSrc", destination = "HIDKeyboardModifierMappingDst" }
}
public enum MappingPolicy {
    public static let caps: UInt64 = 0x700000039
    public static let f18: UInt64 = 0x70000006d
    public static func validate(_ mappings: [KeyMapping]) throws {
        guard Set(mappings.map(\.source)).count == mappings.count else {
            throw HelperError("중복된 키 설정이 있어 변경하지 않았습니다. 기존 키 매핑 도구의 설정을 확인해 주세요.")
        }
    }
    public static func applying(to mappings: [KeyMapping]) throws -> [KeyMapping] {
        try validate(mappings)
        if let current = mappings.first(where: { $0.source == caps }) {
            guard current.destination == caps || current.destination == f18 else {
                throw HelperError("Caps Lock에 다른 기능이 지정되어 있습니다. 기존 키 매핑 설정을 해제한 뒤 다시 시도해 주세요.")
            }
            if current.destination == f18 { return mappings }
        }
        return mappings.filter { $0.source != caps } + [KeyMapping(caps, f18)]
    }
    public static func restoring(_ current: [KeyMapping], original: [KeyMapping]) throws -> [KeyMapping] {
        try validate(current); try validate(original)
        guard let capsMapping = current.first(where: { $0.source == caps }) else { return current }
        let previous = original.first { $0.source == caps }
        // Restore is idempotent, including partial recovery after a previous attempt.
        if capsMapping == previous { return current }
        guard capsMapping.destination == f18 else {
            throw HelperError("설치 후 Caps Lock 설정이 다른 값으로 바뀌었습니다. 자동 실행은 해제했지만 현재 키 설정은 덮어쓰지 않습니다. 복원 기록은 보관됩니다.")
        }
        return current.filter { $0.source != caps } + (previous.map { [$0] } ?? [])
    }
    public static func uniform(_ devices: [[KeyMapping]]) throws -> [KeyMapping] {
        guard let first = devices.first else { throw HelperError("연결된 키보드를 찾지 못했습니다. 키보드를 연결하고 다시 시도해 주세요.") }
        for map in devices {
            try validate(map)
            guard equivalent(first, map) else {
                throw HelperError("키보드마다 키 설정이 다릅니다. 기존 설정 보호를 위해 변경하지 않았습니다. 외장 키보드를 분리한 뒤 다시 시도해 주세요.")
            }
        }
        return first
    }
    public static func equivalent(_ a: [KeyMapping], _ b: [KeyMapping]) -> Bool {
        a.sorted { $0.source < $1.source } == b.sorted { $0.source < $1.source }
    }
}
