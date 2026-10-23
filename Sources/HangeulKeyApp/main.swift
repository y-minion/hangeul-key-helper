import AppKit
import KeyCore

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let demo = CommandLine.arguments.contains("--demo")
    let service = Installation(paths: InstallPaths(home: FileManager.default.homeDirectoryForCurrentUser), system: MacSystem())
    let queue = DispatchQueue(label: "app.hangeulkey.operations")
    var window: NSWindow!
    let mappingStatus = NSTextField(wrappingLabelWithString: "키 설정을 확인하고 있습니다…")
    let loginStatus = NSTextField(wrappingLabelWithString: "로그인 자동 적용을 확인하고 있습니다…")
    let shortcutStatus = NSTextField(wrappingLabelWithString: "아래 설정과 직접 입력 테스트가 필요합니다.")
    let notice = NSTextField(wrappingLabelWithString: "")
    var applyButton: NSButton!
    var restoreButton: NSButton!
    var refreshButton: NSButton!
    var testButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        buildWindow()
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func createMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        menu.addItem(app)
        let submenu = NSMenu()
        submenu.addItem(withTitle: "한영키 도우미 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = submenu
        let edit = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let edits = NSMenu(title: "편집")
        edits.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edits.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edits.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edits.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edits.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = edits
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }
    func text(_ string: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: string)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }
    func stack(_ views: [NSView], spacing: CGFloat = 10, horizontal: Bool = false) -> NSStackView {
        let view = NSStackView(views: views)
        view.orientation = horizontal ? .horizontal : .vertical
        view.alignment = horizontal ? .centerY : .leading
        view.spacing = spacing
        return view
    }
    func button(_ title: String, _ action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .medium)
        if primary { button.bezelColor = .systemTeal }
        return button
    }
    func card(_ title: String, _ description: String, _ content: [NSView]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let inside = stack([text(title, size: 19, weight: .semibold), text(description, secondary: true)] + content, spacing: 12)
        inside.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inside)
        NSLayoutConstraint.activate([
            inside.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 22),
            inside.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -22),
            inside.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            inside.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -20)
        ])
        // Wrapping labels need a bounded width to calculate their natural height.
        for view in inside.arrangedSubviews {
            view.widthAnchor.constraint(lessThanOrEqualTo: inside.widthAnchor).isActive = true
            if let field = view as? NSTextField, field.isEditable { field.widthAnchor.constraint(equalTo: inside.widthAnchor).isActive = true }
        }
        return box
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "한영키 도우미" + (demo ? " · 미리보기" : "")
        window.minSize = NSSize(width: 680, height: 650)
        window.center()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        window.contentView = scroll
        let body = FlippedView()
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = body
        body.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let heading = stack([
            text("한영키 도우미", size: 13, weight: .semibold, secondary: true),
            text("한영키, 가볍게.", size: 34, weight: .bold),
            text("Caps Lock으로 자연스럽게 전환하세요.\n설정이 끝나면 앱을 닫아도 macOS가 직접 처리합니다.", size: 15, secondary: true)
        ], spacing: 8)
        applyButton = button("한영키 설정 적용", #selector(apply), primary: true)
        refreshButton = button("상태 새로 확인", #selector(refresh))
        restoreButton = button("도우미 설정 복원", #selector(restore))
        let settings = button("키보드 설정 열기 ↗", #selector(openSettings))
        testButton = button("한글·영어 전환 확인했어요", #selector(confirmTest))
        for label in [mappingStatus, loginStatus, shortcutStatus, notice] {
            label.font = .systemFont(ofSize: 13)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        notice.textColor = .secondaryLabelColor
        let input = NSTextField(string: "")
        input.placeholderString = "여기를 누르고 안녕하세요 → Caps Lock → hello"
        input.font = .systemFont(ofSize: 17)
        input.bezelStyle = .roundedBezel
        input.heightAnchor.constraint(equalToConstant: 40).isActive = true
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        input.setAccessibilityLabel("한영 전환 테스트 입력란")
        let first = card("1   Caps Lock을 한영키로 준비", "현재 키 설정을 보관한 뒤 F18로 바꾸고, 로그인할 때 다시 적용합니다.", [
            mappingStatus, loginStatus, notice, stack([applyButton, refreshButton], horizontal: true),
            text("이후 Caps Lock의 대문자 고정 기능은 사용할 수 없습니다.\n기존 키 매핑 앱은 먼저 종료해 주세요.", size: 12, secondary: true)
        ])
        let second = card("2   단축키를 한 번만 지정", "시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스", [
            text("‘이전 입력 소스 선택’을 켜고 오른쪽 단축키를 더블 클릭하세요.\nCaps Lock을 눌렀을 때 F18이 표시되면 설정 완료입니다."),
            settings,
            text("F18이 안 나오면 ‘보조 키’에서 해당 키보드의 Caps Lock 설정을 확인하세요.\n이미 F18로 지정했다면 이 단계는 건너뛰어도 됩니다.", size: 12, secondary: true)
        ])
        let third = card("3   직접 전환해 보기", "이 앱과 평소 쓰는 앱에서 한글·영어를 번갈아 입력해 보세요.", [input, testButton, shortcutStatus])
        let footer = stack([
            text("외장 키보드를 나중에 연결했다면 다시 적용해 주세요.\n입력 소스가 3개 이상이면 한글·영어 외의 언어로 전환될 수 있습니다.\nmacOS 버전에 따라 동작이 달라질 수 있으며, 지연 0을 보장하지 않습니다.", size: 12, secondary: true),
            stack([restoreButton, button("사용 안내", #selector(help))], horizontal: true)
        ], spacing: 12)
        let all = stack([heading, first, second, third, footer], spacing: 18)
        all.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(all)
        NSLayoutConstraint.activate([
            all.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 32),
            all.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -32),
            all.topAnchor.constraint(equalTo: body.topAnchor, constant: 26),
            all.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -26)
        ])
        for view in [heading, first, second, third, footer] { view.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true }
    }
    func setBusy(_ value: Bool) {
        [applyButton, restoreButton, refreshButton].forEach { $0?.isEnabled = !value }
    }
    @objc func refresh() {
        shortcutStatus.stringValue = "입력 소스 단축키는 직접 확인해 주세요. 키 매핑만으로 전환 성공을 판단하지 않습니다."
        if demo {
            mappingStatus.stringValue = "●  키 변경 · 아직 적용하지 않음"
            loginStatus.stringValue = "○  로그인 자동 적용 · 아직 등록하지 않음"
            notice.stringValue = "미리보기 모드입니다. 어떤 버튼을 눌러도 실제 키 설정은 바뀌지 않습니다."
            return
        }
        setBusy(true)
        queue.async {
            do {
                let maps = try MappingPolicy.uniform(self.service.system.mappings())
                let mapped = maps.contains(KeyMapping(MappingPolicy.caps, MappingPolicy.f18))
                let saved = try self.service.record()
                let loaded = try self.service.system.isLoaded(Installation.label)
                let legacy = try self.service.legacyConflict()
                DispatchQueue.main.async {
                    self.mappingStatus.stringValue = mapped ? "●  키 변경 · F18 적용됨" : "○  키 변경 · 아직 적용하지 않음"
                    self.loginStatus.stringValue = (saved?.enabled == true && loaded) ? "●  로그인 자동 적용 · 등록됨 (재로그인 후 확인 권장)" : "○  로그인 자동 적용 · 미등록 또는 확인 필요"
                    self.notice.stringValue = legacy ? "기존 게시글의 자동 설정이 감지됐습니다. ‘사용 안내’에서 전환 방법을 확인해 주세요." : (mapped && saved == nil ? "이미 적용된 F18 설정을 확인했습니다. 이 도우미를 쓰기 전 설정은 복원 시에도 유지합니다." : "입력 내용은 저장하거나 전송하지 않습니다.")
                    self.setBusy(false)
                    self.applyButton.isEnabled = !legacy
                    self.restoreButton.isEnabled = saved != nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.mappingStatus.stringValue = "키 설정 확인 필요"
                    self.loginStatus.stringValue = "자동 실행 상태 확인 필요"
                    self.notice.stringValue = error.localizedDescription
                    self.setBusy(false)
                }
            }
        }
    }
    func perform(_ work: @escaping () throws -> Void, success: String) {
        if demo { show("미리보기", "실제 설정은 변경하지 않았습니다."); return }
        setBusy(true)
        notice.stringValue = "설정을 처리하고 있습니다…"
        queue.async {
            let failure: Error?
            do { try work(); failure = nil } catch { failure = error }
            DispatchQueue.main.async {
                self.refresh()
                self.show(failure == nil ? "확인" : "설정 확인이 필요합니다", failure?.localizedDescription ?? success)
            }
        }
    }
    @objc func apply() {
        guard demo || ask("한영키 설정을 적용할까요?", "Caps Lock을 F18로 바꾸고 로그인 자동 적용을 등록합니다. 대문자 고정 기능은 없어집니다. 다른 키 매핑은 보존하며, ‘도우미 설정 복원’으로 되돌릴 수 있습니다.", button: "적용") else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/key-agent")
        perform({ try self.service.install(helperSource: helper) }, success: "키 변경과 로그인 자동 적용을 설정했습니다. 이제 2단계에서 F18 단축키를 지정하고 직접 전환해 보세요.")
    }
    @objc func restore() {
        guard demo || ask("도우미 설정을 복원할까요?", "도우미의 자동 실행을 해제하고 Caps Lock을 도우미 사용 전 상태로 돌립니다. 기존에 F18이었다면 그대로 유지됩니다. 시스템 설정에서 직접 바꾼 입력 소스 단축키는 직접 복원해야 합니다. 설정했던 외장 키보드는 연결해 주세요.", button: "복원") else { return }
        perform({ try self.service.restore() }, success: "도우미가 관리한 설정을 복원했습니다. 필요하면 시스템 설정에서 입력 소스 단축키도 직접 돌려놓으세요.")
    }
    @objc func confirmTest() { shortcutStatus.stringValue = "✓  이번 사용 중 전환을 직접 확인했습니다. 키보드·단축키를 바꾸면 다시 확인해 주세요." }
    @objc func openSettings() {
        if demo { show("키보드 설정", "실제 앱에서는 시스템 설정의 키보드 화면을 엽니다."); return }
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    }
    @objc func help() {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/사용안내.html")
        if !NSWorkspace.shared.open(url) { show("사용 안내", "시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 ‘이전 입력 소스 선택’을 F18로 지정하세요.") }
    }
    func ask(_ title: String, _ message: String, button: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: button); alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func show(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "확인"); alert.runModal()
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
