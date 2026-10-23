import Foundation
import Darwin

public struct CommandResult { public let status: Int32; public let output: String }
public enum CommandRunner {
    // A file avoids pipe-buffer deadlock on verbose system output. No shell interpolation.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 12) throws -> CommandResult {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hangeul-command-" + UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if ended.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw HelperError("시스템 응답 시간이 초과됐습니다. 상태를 새로 확인한 뒤 다시 시도해 주세요.")
        }
        let output = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        return CommandResult(status: process.terminationStatus, output: output)
    }
}

public final class MacSystem: SystemAccess {
    public init() {}
    private var domain: String { "gui/\(getuid())" }
    public func mappings() throws -> [[KeyMapping]] {
        let result = try CommandRunner.run("/usr/bin/hidutil", ["property", "--matching", "keyboard", "--get", "UserKeyMapping"])
        guard result.status == 0 else { throw HelperError("키 설정을 읽지 못했습니다.\n" + result.output) }
        return try HIDParser.parse(result.output)
    }
    public func setMappings(_ mappings: [KeyMapping]) throws {
        try MappingPolicy.validate(mappings)
        let json = try JSONEncoder().encode(["UserKeyMapping": mappings])
        let result = try CommandRunner.run("/usr/bin/hidutil", ["property", "--matching", "keyboard", "--set", String(decoding: json, as: UTF8.self)])
        guard result.status == 0 else { throw HelperError("키 설정 적용에 실패했습니다. macOS 응답:\n" + result.output) }
    }
    public func isLoaded(_ label: String) throws -> Bool {
        let result = try CommandRunner.run("/bin/launchctl", ["print", domain + "/" + label])
        if result.status == 0 { return true }
        if result.status == 113 || result.status == 3 { return false }
        throw HelperError("로그인 자동 실행 상태를 확인하지 못했습니다.\n" + result.output)
    }
    public func loadAgent(at url: URL) throws {
        try unloadAgent(Installation.label)
        let result = try CommandRunner.run("/bin/launchctl", ["bootstrap", domain, url.path])
        guard result.status == 0 else { throw HelperError("로그인 자동 적용 등록에 실패했습니다. '시스템 설정 → 일반 → 로그인 항목'에서 허용 상태를 확인해 주세요.\n" + result.output) }
        guard try isLoaded(Installation.label) else { throw HelperError("로그인 자동 적용 등록을 확인하지 못했습니다.") }
    }
    public func unloadAgent(_ label: String) throws {
        guard try isLoaded(label) else { return }
        let result = try CommandRunner.run("/bin/launchctl", ["bootout", domain + "/" + label])
        guard result.status == 0 else { throw HelperError("로그인 자동 실행을 해제하지 못했습니다.\n" + result.output) }
    }
}
