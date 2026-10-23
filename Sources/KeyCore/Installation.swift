import Foundation
import Darwin
public protocol SystemAccess {
    func mappings() throws -> [[KeyMapping]]
    func setMappings(_ mappings: [KeyMapping]) throws
    func isLoaded(_ label: String) throws -> Bool
    func loadAgent(at url: URL) throws
    func unloadAgent(_ label: String) throws
}
public struct InstallPaths {
    public let home: URL
    public init(home: URL) { self.home = home }
    public var support: URL { home.appendingPathComponent("Library/Application Support/HangeulKeyHelper") }
    public var state: URL { support.appendingPathComponent("state.json") }
    public var helper: URL { support.appendingPathComponent("key-agent") }
    public var agent: URL { home.appendingPathComponent("Library/LaunchAgents/app.hangeulkey.helper.plist") }
    public var legacy: URL { home.appendingPathComponent("Library/LaunchAgents/com.user.capslock.plist") }
}
public struct InstallRecord: Codable {
    public var schema = 2
    public let original: [KeyMapping]
    public var enabled: Bool
    // A backup alone does not establish ownership. Set only immediately before an OS write.
    public var mappingAttempted = false
    // A successful no-op install also establishes a baseline (e.g. preexisting F18).
    public var baselineEstablished = false
    public init(original: [KeyMapping], enabled: Bool) { self.original = original; self.enabled = enabled }
}
public final class Installation {
    public static let label = "app.hangeulkey.helper"
    public let paths: InstallPaths
    public let system: SystemAccess
    public init(paths: InstallPaths, system: SystemAccess) { self.paths = paths; self.system = system }
    public func record() throws -> InstallRecord? {
        guard FileManager.default.fileExists(atPath: paths.state.path) else { return nil }
        let result = try JSONDecoder().decode(InstallRecord.self, from: Data(contentsOf: paths.state))
        guard result.schema == 2 else { throw HelperError("다른 버전의 복원 기록입니다. 기존 기록을 보존하기 위해 중단했습니다.") }
        try MappingPolicy.validate(result.original)
        return result
    }
    public func legacyConflict() throws -> Bool {
        if FileManager.default.fileExists(atPath: paths.legacy.path) { return true }
        return try system.isLoaded("com.user.capslock")
    }
    public func install(helperSource: URL) throws {
        try withLock {
            guard try !legacyConflict() else {
                throw HelperError("게시글의 기존 자동 설정(com.user.capslock)이 남아 있습니다. 두 설정이 충돌하지 않도록 기존 자동 실행을 먼저 해제해 주세요. 현재 키 설정과 기존 파일은 변경하지 않았습니다. 앱의 '사용 안내'를 확인해 주세요.")
            }
            let before = try MappingPolicy.uniform(system.mappings())
            let after = try MappingPolicy.applying(to: before)
            let existing = try record()
            var saved: InstallRecord
            if let existing, existing.mappingAttempted || existing.baselineEstablished {
                saved = existing
            } else {
                saved = InstallRecord(original: before, enabled: false)
            }
            saved.enabled = false
            try save(saved) // Recovery metadata precedes every mutation.
            try FileManager.default.createDirectory(at: paths.agent.deletingLastPathComponent(), withIntermediateDirectories: true)
            let executable = try Data(contentsOf: helperSource)
            try executable.write(to: paths.helper, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.helper.path)
            let plist: [String: Any] = [
                "Label": Self.label,
                "ProgramArguments": [paths.helper.path, "--reapply"],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "StandardOutPath": paths.support.appendingPathComponent("login.log").path,
                "StandardErrorPath": paths.support.appendingPathComponent("login-error.log").path
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: paths.agent, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.agent.path)
            try writeVerified(after, expectedBefore: before) {
                saved.mappingAttempted = true
                try self.save(saved)
            }
            saved.baselineEstablished = true
            saved.enabled = true
            try save(saved)
            do { try system.loadAgent(at: paths.agent) }
            catch {
                saved.enabled = false
                try save(saved)
                throw HelperError("키 변경은 적용됐지만 로그인 자동 적용을 등록하지 못했습니다. 다시 적용하거나 '도우미 설정 복원'을 선택할 수 있습니다.\n\n" + error.localizedDescription)
            }
        }
    }
    public func reapply() throws {
        // An orphaned helper must not recreate an installation after restoration.
        guard FileManager.default.fileExists(atPath: paths.state.path) else { return }
        try withLock {
            guard var saved = try record(), saved.enabled else { return }
            guard try !legacyConflict() else { throw HelperError("기존 자동 설정과 충돌하여 재적용하지 않았습니다.") }
            let before = try MappingPolicy.uniform(system.mappings())
            try writeVerified(MappingPolicy.applying(to: before), expectedBefore: before) {
                saved.mappingAttempted = true
                try self.save(saved)
            }
        }
    }
    public func restore() throws {
        try withLock {
            guard var saved = try record() else { throw HelperError("이 도우미가 만든 복원 기록이 없습니다. 기존 키 설정은 변경하지 않았습니다.") }
            saved.enabled = false
            try save(saved) // A queued login helper will see disabled after acquiring this lock.
            try system.unloadAgent(Self.label)
            if FileManager.default.fileExists(atPath: paths.agent.path) { try FileManager.default.removeItem(at: paths.agent) }
            if saved.mappingAttempted {
                let before = try MappingPolicy.uniform(system.mappings())
                try writeVerified(MappingPolicy.restoring(before, original: saved.original), expectedBefore: before)
            }
            if FileManager.default.fileExists(atPath: paths.helper.path) { try FileManager.default.removeItem(at: paths.helper) }
            try FileManager.default.removeItem(at: paths.state)
            // Keep the support directory and lock inode to avoid races with queued processes.
        }
    }
    private func writeVerified(_ after: [KeyMapping], expectedBefore before: [KeyMapping], beforeWrite: () throws -> Void = {}) throws {
        let current = try MappingPolicy.uniform(system.mappings())
        guard MappingPolicy.equivalent(current, before) else {
            throw HelperError("작업 중 키 설정이 변경되어 중단했습니다. 다른 키 매핑 앱을 종료하고 다시 시도해 주세요.")
        }
        if !MappingPolicy.equivalent(before, after) {
            try beforeWrite()
            try system.setMappings(after)
        }
        let actual = try MappingPolicy.uniform(system.mappings())
        guard MappingPolicy.equivalent(actual, after) else {
            throw HelperError("macOS에서 키 설정 적용을 확인하지 못했습니다. 복원 기록은 보관했습니다. 상태를 다시 확인해 주세요.")
        }
    }
    private func save(_ record: InstallRecord) throws {
        try JSONEncoder().encode(record).write(to: paths.state, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.state.path)
    }
    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let descriptor = open(paths.support.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw HelperError("설정 작업 잠금을 만들지 못했습니다.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw HelperError("다른 설정 작업이 진행 중입니다.") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
