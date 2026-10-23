import XCTest
@testable import KeyCore
final class FakeSystem: SystemAccess {
    var devices: [[KeyMapping]] = [[]]
    var loaded = Set<String>()
    var failLoad = false
    var ignoreWrites = false
    var failUnload = false
    func mappings() throws -> [[KeyMapping]] { devices }
    func setMappings(_ mappings: [KeyMapping]) throws { if !ignoreWrites { devices = devices.map { _ in mappings } } }
    func isLoaded(_ label: String) throws -> Bool { loaded.contains(label) }
    func loadAgent(at url: URL) throws {
        if failLoad { throw HelperError("registration failed") }
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertNil(plist["KeepAlive"])
        let args = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(args.count, 2)
        XCTAssertEqual(args[1], "--reapply")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: args[0]))
        loaded.insert(Installation.label)
    }
    func unloadAgent(_ label: String) throws {
        if failUnload { throw HelperError("unload failed") }
        loaded.remove(label)
    }
}
final class InstallationTests: XCTestCase {
    var home: URL!
    var paths: InstallPaths!
    var system: FakeSystem!
    var installation: Installation!
    var helper: URL!
    let target = KeyMapping(30064771129, 30064771181)
    let unrelated = KeyMapping(30064771076, 30064771077)
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " 한영 test")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = InstallPaths(home: home)
        system = FakeSystem()
        installation = Installation(paths: paths, system: system)
        helper = home.appendingPathComponent("source-helper")
        try Data("fake executable".utf8).write(to: helper)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    func testInstallAndRestorePreserveLaterUnrelatedChange() throws {
        try installation.install(helperSource: helper)
        XCTAssertEqual(system.devices, [[target]])
        XCTAssertTrue(try XCTUnwrap(installation.record()).enabled)
        system.devices = [[target, unrelated]]
        try installation.restore()
        XCTAssertEqual(system.devices, [[unrelated]])
        XCTAssertNil(try installation.record())
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.agent.path))
        XCTAssertFalse(system.loaded.contains(Installation.label))
    }
    func testReinstallDoesNotReplaceOriginalBackup() throws {
        try installation.install(helperSource: helper)
        try installation.install(helperSource: helper)
        XCTAssertEqual(try XCTUnwrap(installation.record()).original, [])
        try installation.restore()
        XCTAssertEqual(system.devices, [[]])
    }
    func testPreexistingF18RemainsAfterRestore() throws {
        system.devices = [[target]]
        try installation.install(helperSource: helper)
        try installation.restore()
        XCTAssertEqual(system.devices, [[target]])
    }
    func testLoginMergesCurrentMappingsInsteadOfReplayingStaleArray() throws {
        try installation.install(helperSource: helper)
        system.devices = [[unrelated]]
        try installation.reapply()
        XCTAssertEqual(system.devices, [[unrelated, target]])
    }
    func testFailedRegistrationRetainsRecoveryAndDisablesReapply() throws {
        system.failLoad = true
        XCTAssertThrowsError(try installation.install(helperSource: helper))
        XCTAssertFalse(try XCTUnwrap(installation.record()).enabled)
        system.devices = [[]]
        try installation.reapply()
        XCTAssertEqual(system.devices, [[]])
        try installation.restore()
        XCTAssertNil(try installation.record())
    }
    func testFailedWriteIsDetectedAndOriginalBackupSurvives() throws {
        system.ignoreWrites = true
        XCTAssertThrowsError(try installation.install(helperSource: helper))
        XCTAssertNotNil(try installation.record())
        XCTAssertFalse(system.loaded.contains(Installation.label))
    }
    func testLegacyFileBlocksWithoutChangingMapping() throws {
        try FileManager.default.createDirectory(at: paths.legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: paths.legacy)
        XCTAssertThrowsError(try installation.install(helperSource: helper))
        XCTAssertEqual(system.devices, [[]])
        XCTAssertNil(try installation.record())
    }
    func testLegacyLoadedJobBlocksEvenWithoutFile() {
        system.loaded.insert("com.user.capslock")
        XCTAssertThrowsError(try installation.install(helperSource: helper))
        XCTAssertEqual(system.devices, [[]])
    }
    func testMixedDevicesCannotBeOverwritten() {
        system.devices = [[], [unrelated]]
        XCTAssertThrowsError(try installation.install(helperSource: helper))
        XCTAssertEqual(system.devices, [[], [unrelated]])
    }
    func testRestoreConflictStopsAutomationButKeepsRecovery() throws {
        try installation.install(helperSource: helper)
        let changed = KeyMapping(30064771129, 30064771113)
        system.devices = [[changed]]
        XCTAssertThrowsError(try installation.restore())
        XCTAssertEqual(system.devices, [[changed]])
        XCTAssertFalse(system.loaded.contains(Installation.label))
        XCTAssertFalse(try XCTUnwrap(installation.record()).enabled)
    }
    func testFailedUnloadKeepsBackupAndDoesNotChangeKeys() throws {
        try installation.install(helperSource: helper)
        system.failUnload = true
        XCTAssertThrowsError(try installation.restore())
        XCTAssertEqual(system.devices, [[target]])
        XCTAssertFalse(try XCTUnwrap(installation.record()).enabled)
    }
    func testMissingStateDoesNotAllowUnownedRestore() {
        system.devices = [[target]]
        XCTAssertThrowsError(try installation.restore())
        XCTAssertEqual(system.devices, [[target]])
    }
    func testFailureBeforeKeyWriteCannotOwnLaterExternalF18() throws {
        let missingHelper = home.appendingPathComponent("missing-helper")
        XCTAssertThrowsError(try installation.install(helperSource: missingHelper))
        system.devices = [[target, unrelated]] // Another tool changes the keys after our failure.
        try installation.restore()
        XCTAssertEqual(system.devices, [[target, unrelated]])
        XCTAssertNil(try installation.record())
    }
    func testRetryAfterPreparationFailureUsesFreshBaseline() throws {
        XCTAssertThrowsError(try installation.install(helperSource: home.appendingPathComponent("missing")))
        system.devices = [[target, unrelated]]
        try installation.install(helperSource: helper)
        try installation.restore()
        XCTAssertEqual(system.devices, [[target, unrelated]])
    }
    func testLoginOwnsNewWriteEvenWhenInstallNeededNoWrite() throws {
        system.devices = [[target]]
        try installation.install(helperSource: helper)
        system.devices = [[unrelated]] // Mapping disappears on reboot.
        try installation.reapply()
        XCTAssertEqual(system.devices, [[unrelated, target]])
        try installation.restore()
        XCTAssertEqual(system.devices, [[unrelated, target]]) // Original F18 is preserved.
    }

    func testReinstallAfterMappingLossKeepsEstablishedPreexistingF18Baseline() throws {
        system.devices = [[target]]
        try installation.install(helperSource: helper)
        system.devices = [[unrelated]] // Keyboard reconnection loses only the earlier mapping.
        try installation.install(helperSource: helper)
        try installation.restore()
        XCTAssertEqual(system.devices, [[unrelated, target]])
    }

    func testFailedUpgradeDoesNotForgetEstablishedPreexistingBaseline() throws {
        system.devices = [[target]]
        try installation.install(helperSource: helper)
        XCTAssertThrowsError(try installation.install(helperSource: home.appendingPathComponent("missing")))
        system.devices = [[]]
        try installation.install(helperSource: helper)
        try installation.restore()
        XCTAssertEqual(system.devices, [[target]])
    }

}
