import XCTest
@testable import KeyCore
final class MappingTests: XCTestCase {
    let caps: UInt64 = 30064771129
    let f18: UInt64 = 30064771181
    let other = KeyMapping(30064771076, 30064771077)
    func testApplyPreservesUnrelatedMapping() throws {
        XCTAssertEqual(try MappingPolicy.applying(to: [other]), [other, KeyMapping(caps, f18)])
    }
    func testApplyRejectsExistingCapsToEscape() {
        XCTAssertThrowsError(try MappingPolicy.applying(to: [KeyMapping(caps, 30064771113)]))
    }
    func testApplyIsIdempotent() throws {
        XCTAssertEqual(try MappingPolicy.applying(to: [other, KeyMapping(caps, f18)]), [other, KeyMapping(caps, f18)])
    }
    func testRestoreKeepsLaterUnrelatedChanges() throws {
        XCTAssertEqual(try MappingPolicy.restoring([other, KeyMapping(caps, f18)], original: []), [other])
    }
    func testRestoreRetainsF18WhenItPredatedInstallation() throws {
        XCTAssertEqual(try MappingPolicy.restoring([KeyMapping(caps, f18)], original: [KeyMapping(caps, f18)]), [KeyMapping(caps, f18)])
    }
    func testRestoreDoesNotOverwriteAnotherAppsCapsChange() {
        XCTAssertThrowsError(try MappingPolicy.restoring([KeyMapping(caps, 30064771113)], original: []))
    }
    func testRestoreAfterRebootDoesNotReintroduceOldUnrelatedMappings() throws {
        XCTAssertEqual(try MappingPolicy.restoring([], original: [other]), [])
    }
    func testMixedDevicesFailClosed() {
        XCTAssertThrowsError(try MappingPolicy.uniform([[other], []]))
    }
    func testUniformIgnoresOrdering() throws {
        XCTAssertEqual(try MappingPolicy.uniform([[other, KeyMapping(caps, f18)], [KeyMapping(caps, f18), other]]), [other, KeyMapping(caps, f18)])
    }
    func testDuplicateSourcesAreRejected() {
        XCTAssertThrowsError(try MappingPolicy.applying(to: [other, other]))
    }
    func testNoKeyboardIsNotAnEmptyMap() {
        XCTAssertThrowsError(try MappingPolicy.uniform([]))
    }
}
final class HIDParserTests: XCTestCase {
    func testModernTableIncludesMappedAndUnmappedDevices() throws {
        let text = """
        RegistryID  Key                   Value
        100000cc6   UserKeyMapping   (
            {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100001d4b   UserKeyMapping   (null)
        """
        XCTAssertEqual(try HIDParser.parse(text), [[KeyMapping(30064771129, 30064771181)], []])
    }
    func testLegacyArray() throws {
        XCTAssertEqual(try HIDParser.parse("({HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181;})"), [[KeyMapping(30064771129, 30064771181)]])
    }
    func testLegacyNull() throws { XCTAssertEqual(try HIDParser.parse("(null)"), [[]]) }
    func testEmptyTableIsNoKeyboard() throws { XCTAssertEqual(try HIDParser.parse("RegistryID Key Value\n"), []) }
    func testMalformedOutputMustNotBeTreatedAsEmptyMapping() {
        for text in ["permission denied", "", "RegistryID Key Value\n123 UserKeyMapping (garbage)", "({HIDKeyboardModifierMappingSrc = invalid;})"] {
            XCTAssertThrowsError(try HIDParser.parse(text), text)
        }
    }
}
