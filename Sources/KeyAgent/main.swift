import Foundation
import KeyCore
let installation = Installation(paths: InstallPaths(home: FileManager.default.homeDirectoryForCurrentUser), system: MacSystem())
do {
    switch CommandLine.arguments.dropFirst().first {
    case "--reapply":
        try installation.reapply()
        print("로그인 재적용 확인 완료")
    case "--status":
        let devices = try installation.system.mappings()
        let maps = try MappingPolicy.uniform(devices)
        let record = try installation.record()
        let loaded = try installation.system.isLoaded(Installation.label)
        print("키보드 서비스: \(devices.count)")
        print("Caps Lock → F18: \(maps.contains(KeyMapping(MappingPolicy.caps, MappingPolicy.f18)) ? "적용됨" : "미적용")")
        print("도우미 복원 기록: \(record == nil ? "없음" : "있음")")
        print("도우미 로그인 작업: \(loaded ? "등록됨" : "미등록")")
        print("기존 게시글 자동 설정: \(try installation.legacyConflict() ? "감지됨" : "없음")")
        print("입력 소스 단축키: 시스템 설정에서 직접 확인 필요")
    default:
        print("한영키 도우미 진단: key-agent --status (읽기 전용)\n로그인 재적용: key-agent --reapply (설치 기록이 있을 때만 실행)")
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
