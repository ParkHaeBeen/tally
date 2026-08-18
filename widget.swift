// Tally — a menu-bar widget that keeps your reviews, issues, notes and CI
// in one place. Everything is read-only; nothing is ever pushed anywhere.
//
//   build:  ./build.sh          run:  ./tally  (or open Tally.app)
//   dump:   ./tally --dump      shows the same content as text

import AppKit
import UserNotifications

// ─────────────────────────────── 경로 ───────────────────────────────

/// 데이터 폴더를 실행 시점에 찾는다.
/// 예전에는 컴파일 시점의 #filePath 를 썼는데, 상대 경로로 잡히면
/// launchd 로 띄울 때 작업 폴더가 "/" 라서 아무 파일도 못 읽었다.
func resolveDir() -> URL {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.appendingPathComponent("tally")
    if let p = ProcessInfo.processInfo.environment["MW_DIR"], !p.isEmpty {
        return URL(fileURLWithPath: p)
    }
    var d = (Bundle.main.executableURL?.resolvingSymlinksInPath()
             ?? URL(fileURLWithPath: CommandLine.arguments[0]).absoluteURL)
        .deletingLastPathComponent()
    if d.lastPathComponent == "MacOS" {          // .app/Contents/MacOS → .app 의 상위
        d.deleteLastPathComponent()              // Contents
        d.deleteLastPathComponent()              // MyWidget.app
        d.deleteLastPathComponent()              // repo folder
    }
    if fm.fileExists(atPath: d.appendingPathComponent("config.sh").path) { return d }
    return home
}

let dir = resolveDir()
let dataURL = dir.appendingPathComponent("data.json")
let memoURL = dir.appendingPathComponent("memo.txt")
let stateURL = dir.appendingPathComponent("ui-state.json")
let doneURL = dir.appendingPathComponent("done.txt")
let fetchURL = dir.appendingPathComponent("fetch.sh")
let configURL = dir.appendingPathComponent("config.sh")
let agentID = "com.tally.agent"
let agentURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(agentID).plist")

let logURL = dir.appendingPathComponent("tally.log")

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
    let line = "[\(f.string(from: Date()))] \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}


// ─────────────────────────── 화면에 보이는 말 ───────────────────────────

/// UI strings. Set MW_LANG=ko|en in config.sh.
enum Strings {
    static var lang = "en"

    static let table: [String: [String: String]] = [
        "search":        ["en": "Search titles",     "ko": "제목 검색"],
        "noMatches":     ["en": "no matches",        "ko": "걸린 항목 없음"],
        "more":          ["en": "+ %d more",         "ko": "+ %d개 더"],
        "less":          ["en": "− show fewer",      "ko": "− 줄여 보기"],
        "addMemo":       ["en": "+ Add note",        "ko": "+ 메모 추가"],
        "addMemoTitle":  ["en": "New note",          "ko": "메모 추가"],
        "addMemoInfo":   ["en": "The title shows in the list; details unfold when clicked.",
                          "ko": "제목은 목록에 보이고, 상세는 눌렀을 때 펼쳐집니다."],
        "titleField":    ["en": "Title — e.g. ask DBA about the query plan",
                          "ko": "제목 — 예: DBA한테 실행계획 문의"],
        "detailField":   ["en": "Details (leave empty if none)",
                          "ko": "상세 (없으면 비워두세요)"],
        "detailTitle":   ["en": "Details",           "ko": "상세 내용"],
        "detailHint":    ["en": "What, why, how far", "ko": "무엇을, 왜, 어디까지"],
        "writeDetail":   ["en": "add details…",      "ko": "상세 적기…"],
        "add":           ["en": "Add",               "ko": "추가"],
        "save":          ["en": "Save",              "ko": "저장"],
        "cancel":        ["en": "Cancel",            "ko": "취소"],
        "never":         ["en": "not fetched",       "ko": "조회 전"],
        "fetching":      ["en": "fetching",          "ko": "조회 중"],
        "justNow":       ["en": "just now",          "ko": "방금"],
        "minsAgo":       ["en": "%dm ago",           "ko": "%d분 전"],
        "hoursAgo":      ["en": "%dh ago",           "ko": "%d시간 전"],
        "daysAgo":       ["en": "%dd ago",           "ko": "%d일 전"],
        "failedPrefix":  ["en": "fetch failed · ",   "ko": "조회 실패 · "],
        "staleSuffix":   ["en": " old",              "ko": " 데이터"],
        "menuShow":      ["en": "Show window",       "ko": "위젯 보이기"],
        "menuRefresh":   ["en": "Refresh now",       "ko": "지금 새로고침"],
        "menuReanchor":  ["en": "Snap under menu bar", "ko": "메뉴바 아래로 다시 붙이기"],
        "menuAddMemo":   ["en": "New note",          "ko": "메모 추가"],
        "menuOpenMemo":  ["en": "Open notes file",   "ko": "메모 파일 열기"],
        "menuOpenDone":  ["en": "Open finished notes", "ko": "완료한 메모 열기"],
        "menuUndo":      ["en": "Undo last finished", "ko": "마지막 완료 되돌리기"],
        "menuOpenConfig":["en": "Open config file",  "ko": "설정 파일 열기"],
        "menuAutostart": ["en": "Start at login",    "ko": "로그인 시 자동 시작"],
        "menuQuit":      ["en": "Quit",              "ko": "종료"],
        "ciFail":        ["en": "CI failed",         "ko": "CI 실패"],
        "ciOk":          ["en": "CI passed",         "ko": "CI 성공"],
        "ciRun":         ["en": "CI started",        "ko": "CI 시작"],
        "memoRestored":  ["en": "Note restored",     "ko": "메모 되돌림"],
        "nothingToUndo": ["en": "Nothing to restore", "ko": "되돌릴 것이 없습니다"],
        "noFinished":    ["en": "No finished notes yet", "ko": "완료한 메모가 없습니다"],
        "tipRefresh":    ["en": "Refresh now",       "ko": "지금 새로고침"],
        "tipDone":       ["en": "Done — moves to done.txt", "ko": "완료 — done.txt 로 옮깁니다"],
        "tipEdit":       ["en": "Edit details",      "ko": "상세 고치기"],
        "tipShowAll":    ["en": "Show all in this group", "ko": "이 묶음 전부 보기"],
        "tipAddMemo":    ["en": "Title and details together", "ko": "제목과 상세를 함께 적습니다"],
        "memoSection":   ["en": "Notes",             "ko": "메모"],
        "dateFormat":    ["en": "MMM d",             "ko": "M월 d일"],
    ]

    static func t(_ key: String) -> String {
        table[key]?[lang] ?? table[key]?["en"] ?? key
    }
}

/// L("minsAgo", 5) → "5m ago"
func L(_ key: String, _ n: Int? = nil) -> String {
    var out = Strings.t(key)
    if let n { out = out.replacingOccurrences(of: "%d", with: "\(n)") }
    return out
}

// ─────────────────────────────── 테마 ───────────────────────────────

func rgb(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    var v = UInt64(0)
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

struct Theme {
    var surface, head, line, ink, mute, accent, badge, badgeBg, danger: NSColor
    /// 칸 색: (띠 배경, 왼쪽 레일)
    var hues: [String: (NSColor, NSColor)]

    static func named(_ name: String) -> Theme {
        let base = Theme(
            surface: rgb("#1D2427", 0.94), head: rgb("#242D31"), line: rgb("#323D42"),
            ink: rgb("#E6ECEE"), mute: rgb("#8A9BA0"), accent: rgb("#5FB8AE"),
            badge: rgb("#E0A54B"), badgeBg: rgb("#3A2E18"), danger: rgb("#E07A62"),
            hues: [
                "teal": (rgb("#2D4949"), rgb("#6FC9BE")),
                "blue": (rgb("#354754"), rgb("#93C0E6")),
                "amber": (rgb("#4E4430"), rgb("#EEB662")),
                "grey": (rgb("#384245"), rgb("#A3B3B8")),
            ])
        var t = base
        switch name {
        case "sage": t.accent = rgb("#93B98C")
        case "ice": t.accent = rgb("#7FB0DC")
        case "copper": t.accent = rgb("#D08E5C")
        case "deep":
            t.surface = rgb("#131A1C", 0.94); t.head = rgb("#182023")
            t.line = rgb("#263033"); t.ink = rgb("#E9F0F1"); t.mute = rgb("#7C8D92")
        case "soft":
            t.surface = rgb("#252E31", 0.92); t.head = rgb("#2C3639")
            t.line = rgb("#3A4549"); t.ink = rgb("#DDE5E7"); t.mute = rgb("#96A6AA")
        default: break
        }
        return t
    }
}

/// Group colours. fetch.py labels each group with a name from this set, so the
/// widget stays free of tracker-specific vocabulary.
func groupColor(_ name: String) -> NSColor {
    switch name {
    case "blue": return rgb("#93C0E6")
    case "green": return rgb("#8FCB9B")
    case "amber": return rgb("#EEB662")
    case "purple": return rgb("#C4A0D6")
    case "dim": return rgb("#78868C")
    case "plain": return rgb("#C6CDD1")
    default: return rgb("#8A9BA0")
    }
}

// ─────────────────────────────── 설정 ───────────────────────────────

struct Config {
    var theme = "titanium"
    var refreshHours = 4.0
    var foldedDefault: Set<String> = ["plane"]
    var fastSeconds = 120.0
    var watchDirs: [String] = []
    var notifyCI = "all"        // all | fail | n
    var maxHeightPct = 55.0
    var rowsPerSection = 8
    var lang = "en"
    var memoTitle = "Notes"
    var sectionOrder = ["code", "issues", "notes", "ci"]

    static func load() -> Config {
        var c = Config()
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return c }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("export MW_") else { continue }
            let body = t.dropFirst("export ".count)
            guard let eq = body.firstIndex(of: "=") else { continue }
            let key = String(body[body.startIndex..<eq])
            var val = String(body[body.index(after: eq)...])
            val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            switch key {
            case "MW_THEME": c.theme = val
            case "MW_REFRESH_HOURS": c.refreshHours = Double(val) ?? 4
            case "MW_FAST_SECONDS": c.fastSeconds = Double(val) ?? 120
            case "MW_NOTIFY_CI":
                let v = val.lowercased()
                c.notifyCI = ["all", "fail", "n"].contains(v) ? v : (v == "y" ? "all" : "n")
            case "MW_MAX_HEIGHT_PCT": c.maxHeightPct = Double(val) ?? 55
            case "MW_ROWS_PER_SECTION": c.rowsPerSection = Int(val) ?? 8
            case "MW_LANG": c.lang = val.lowercased() == "ko" ? "ko" : "en"
            case "MW_TITLE_MEMO": c.memoTitle = val
            case "MW_SECTION_ORDER":
                let list = val.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !list.isEmpty { c.sectionOrder = list }
            case "MW_WATCH_DIRS":
                c.watchDirs = val.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
            case "MW_FOLDED_DEFAULT":
                c.foldedDefault = Set(val.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            default: break
            }
        }
        return c
    }
}

// ───────────────────────────── 데이터 모델 ─────────────────────────────

struct Row {
    var id = ""
    var title = ""
    var url = ""
    var badge = ""
    var ok = false
    var ci = ""          // success / failed / running …
    var ciUrl = ""
    var detail = ""      // 메모 상세
    var kind = "item"    // item | memo
    var mine = false     // 내가 돌린 파이프라인
    var repo = ""        // 리포 약어
    var repoFull = ""    // 리포 전체 이름
    var ref = ""         // 브랜치 또는 파이프라인 ref
    var index = 0        // 메모 순번
}

struct Group {
    var key = ""
    var title = ""
    var color = "plain"     // blue | green | amber | purple | plain | dim
    var rows: [Row] = []
}

struct Section {
    var key = ""
    var title = ""
    var hue = "grey"
    var groups: [Group] = []
    var count: Int { groups.reduce(0) { $0 + $1.rows.count } }
}

// ─────────────────────────── 메모 파일 파싱 ───────────────────────────

struct Memo {
    var title: String
    var detail: String
}

func loadMemos() -> [Memo] {
    guard let text = try? String(contentsOf: memoURL, encoding: .utf8) else { return [] }
    var out: [Memo] = []
    for raw in text.components(separatedBy: .newlines) {
        if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        let indented = raw.hasPrefix(" ") || raw.hasPrefix("\t")
        let body = raw.trimmingCharacters(in: .whitespaces)
        if indented, var last = out.popLast() {
            last.detail = last.detail.isEmpty ? body : last.detail + " " + body
            out.append(last)
        } else {
            out.append(Memo(title: body, detail: ""))
        }
    }
    return out
}

func saveMemos(_ memos: [Memo]) {
    var lines: [String] = []
    for m in memos {
        lines.append(m.title)
        if !m.detail.isEmpty { lines.append("    " + m.detail) }
        lines.append("")
    }
    try? lines.joined(separator: "\n").write(to: memoURL, atomically: true, encoding: .utf8)
}

// ────────────────────────────── UI 상태 ──────────────────────────────

final class UIState {
    var folded: Set<String> = []
    var expandedMemos: Set<String> = []
    var showAll: Set<String> = []
    var frame: NSRect?
    var open = true

    init(config: Config) {
        folded = config.foldedDefault.union(["plane/Backlog"])
        guard let d = try? Data(contentsOf: stateURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if let f = j["folded"] as? [String] { folded = Set(f) }
        if let e = j["memos"] as? [String] { expandedMemos = Set(e) }
        if let o = j["open"] as? Bool { open = o }
        if let a = j["showAll"] as? [String] { showAll = Set(a) }
        if let r = j["frame"] as? [String: Double],
           let x = r["x"], let y = r["y"], let w = r["w"], let h = r["h"] {
            frame = NSRect(x: x, y: y, width: w, height: h)
        }
    }

    func save() {
        var j: [String: Any] = ["folded": Array(folded),
                                "memos": Array(expandedMemos),
                                "showAll": Array(showAll),
                                "open": open]
        if let f = frame {
            j["frame"] = ["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height]
        }
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted]) {
            try? d.write(to: stateURL)
        }
    }
}

/// 원격으로 올린 것을 감지한다.
/// git 에는 올린 뒤에 실행되는 훅이 없지만, 성공하면 로컬의 원격 추적 ref 와
/// 그 reflog 파일이 갱신된다. 그 파일 변화만 지켜보면 훅 설치 없이 알 수 있다.
final class PushWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var pending = false
    private let delay: TimeInterval

    init(dirs: [String], delay: TimeInterval = 25, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.delay = delay
        guard !dirs.isEmpty else { return }
        let info = Unmanaged.passRetained(self).toOpaque()
        var ctx = FSEventStreamContext(version: 0, info: info, retain: nil,
                                       release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<PushWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            _ = count
            for p in list where p.contains("/logs/refs/remotes/")
                || p.contains("/refs/remotes/origin/") {
                me.trigger(p)
                return
            }
        }
        stream = FSEventStreamCreate(
            nil, callback, &ctx, dirs as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer
                                     | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
            log("원격 변화 감시 시작: \(dirs.joined(separator: ", "))")
        }
    }

    /// 여러 파일이 한꺼번에 바뀌므로 한 번만 반응하고, 파이프라인이 만들어질 시간을 준다.
    private func trigger(_ path: String) {
        guard !pending else { return }
        pending = true
        log("원격 갱신 감지: \(path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }
}

/// 맥 알림 대신 우리가 직접 그리는 배너.
/// 시스템 알림은 서명되지 않은 앱에 권한을 주지 않아서(UNErrorDomain 1) 아이콘도 우리 것을
/// 쓸 수 없다. 직접 그리면 상태별로 왼쪽 표시까지 바꿀 수 있고 생김새도 위젯과 맞출 수 있다.
final class Banner {
    enum Kind {
        case ok, fail, run, info

        var glyph: String {
            switch self {
            case .ok: return "✓"
            case .fail: return "✗"
            case .run: return "◍"
            case .info: return "•"
            }
        }
        var color: NSColor {
            switch self {
            case .ok: return rgb("#3FBF8F")
            case .fail: return rgb("#F0705A")
            case .run: return rgb("#E0A54B")
            case .info: return rgb("#8FB8BC")
            }
        }
        var sound: String? {
            switch self {
            case .ok: return "Tink"
            case .fail: return "Basso"
            default: return nil
            }
        }
    }

    private static var stack: [Banner] = []
    private let panel: NSPanel
    private var timer: Timer?
    private let onClick: (() -> Void)?

    static func show(_ kind: Kind, title: String, subtitle: String, body: String,
                     theme: Theme, playSound: Bool = true, onClick: (() -> Void)? = nil) {
        let b = Banner(kind, title: title, subtitle: subtitle, body: body,
                       theme: theme, onClick: onClick)
        stack.append(b)
        b.layout()
        b.appear()
        if playSound, let name = kind.sound { NSSound(named: name)?.play() }
    }

    private init(_ kind: Kind, title: String, subtitle: String, body: String,
                 theme: Theme, onClick: (() -> Void)?) {
        self.onClick = onClick
        let w: CGFloat = 344, h: CGFloat = 74
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = theme.surface.withAlphaComponent(0.74).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        // 왼쪽 상태 표시 — 이 자리가 상태에 따라 바뀐다
        let chip = NSView(frame: NSRect(x: 14, y: h / 2 - 17, width: 34, height: 34))
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 10
        chip.layer?.backgroundColor = kind.color.withAlphaComponent(0.18).cgColor
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = kind.color.withAlphaComponent(0.45).cgColor
        blur.addSubview(chip)

        let glyph = NSTextField(labelWithString: kind.glyph)
        glyph.font = .systemFont(ofSize: 17, weight: .bold)
        glyph.textColor = kind.color
        glyph.alignment = .center
        glyph.frame = NSRect(x: 0, y: 6, width: 34, height: 22)
        chip.addSubview(glyph)

        func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight,
                   _ color: NSColor, mono: Bool = false) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight)
                          : .systemFont(ofSize: size, weight: weight)
            f.textColor = color
            f.lineBreakMode = .byTruncatingTail
            return f
        }

        let x: CGFloat = 58, tw = w - x - 14
        let t = label(title, 12.5, .semibold, kind.color)
        t.frame = NSRect(x: x, y: h - 26, width: tw, height: 17)
        let sub = label(subtitle, 10.5, .regular, theme.mute, mono: true)
        sub.frame = NSRect(x: x, y: h - 43, width: tw, height: 14)
        let bod = label(body, 11.5, .regular, theme.ink)
        bod.frame = NSRect(x: x, y: h - 62, width: tw, height: 16)
        for v in [t, sub, bod] { blur.addSubview(v) }

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        blur.addGestureRecognizer(click)
    }

    @objc private func clicked() {
        onClick?()
        dismiss()
    }

    /// 여러 개가 겹치지 않게 위에서부터 쌓는다.
    private func layout() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let idx = Banner.stack.firstIndex(where: { $0 === self }) ?? 0
        let x = vf.maxX - panel.frame.width - 14
        let y = vf.maxY - panel.frame.height - 10 - CGFloat(idx) * (panel.frame.height + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func appear() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            panel.animator().alphaValue = 1
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        timer?.invalidate()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            Banner.stack.removeAll { $0 === self }
            for (i, b) in Banner.stack.enumerated() { b.reposition(i) }
        }
    }

    private func reposition(_ idx: Int) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.maxX - panel.frame.width - 14
        let y = vf.maxY - panel.frame.height - 10 - CGFloat(idx) * (panel.frame.height + 8)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.2
            panel.animator().setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// ─────────────────────────────── 본체 ───────────────────────────────

final class Widget: NSObject, NSApplicationDelegate, NSTextViewDelegate,
                    NSTextFieldDelegate, NSSearchFieldDelegate,
                    UNUserNotificationCenterDelegate {
    var config = Config.load()
    lazy var theme = Theme.named(config.theme)
    lazy var state = UIState(config: config)

    var statusItem: NSStatusItem!
    var contextMenu: NSMenu!
    var panel: NSPanel!
    var textView: NSTextView!
    var searchField: NSSearchField!
    var syncLabel: NSTextField!
    var refreshButton: NSButton!

    var sections: [Section] = []
    var fetchedAt: Date?
    var fetchErrors: [String] = []
    var fetching = false
    var query = ""
    var timer: Timer?
    var watcher: PushWatcher?
    var fastUntil: Date?
    var lastFetchOK = true
    var prevCI: [String: String] = [:]
    var lastRenderWidth: CGFloat = 0
    var adjusting = false
    var canPostNative = false

    // ── 시작 ──
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Strings.lang = config.lang
        trimLog()
        setupNotifications()
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let w = note.object as? NSWindow, w === self.panel else { return }
            if abs(self.contentWidth() - self.lastRenderWidth) > 2, !self.adjusting {
                self.render()
            }
        }
        buildStatusItem()
        buildPanel()
        reload()
        if state.open { showPanel() }

        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // 라이트/다크가 바뀌면 메뉴바 색을 다시 고른다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.updateStatusTitle()
            }
        }

        scheduleNext()
        watcher = PushWatcher(dirs: config.watchDirs) { [weak self] in
            guard let self else { return }
            // 올린 직후 한동안은 짧은 간격으로 본다 — CI 가 돌기 시작하는 걸 잡기 위해
            self.fastUntil = Date().addingTimeInterval(20 * 60)
            self.fetch()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // 잠든 동안 타이머가 멈췄으므로, 오래됐으면 깨어난 직후 한 번 조회
            if let at = self.fetchedAt,
               Date().timeIntervalSince(at) > self.config.refreshHours * 3600 {
                self.fetch()
            }
        }

        if fetchedAt == nil || Date().timeIntervalSince(fetchedAt!) > config.refreshHours * 3600 {
            fetch()
        }
    }

    /// 로그가 무한히 커지지 않게 마지막 200줄만 남긴다.
    func trimLog() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int, size > 200_000,
              let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: .newlines)
        let keep = lines.suffix(200).joined(separator: "\n")
        try? keep.write(to: logURL, atomically: true, encoding: .utf8)
    }

    // ── 메뉴바 ──
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.addItem(withTitle: L("menuShow"), action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: L("menuRefresh"), action: #selector(fetchNow), keyEquivalent: "r")
        menu.addItem(withTitle: L("menuReanchor"), action: #selector(resetPosition), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menuAddMemo"), action: #selector(addMemo), keyEquivalent: "n")
        menu.addItem(withTitle: L("menuOpenMemo"), action: #selector(openMemo), keyEquivalent: "")
        menu.addItem(withTitle: L("menuOpenDone"), action: #selector(openDone), keyEquivalent: "")
        menu.addItem(withTitle: L("menuUndo"), action: #selector(undoDone), keyEquivalent: "z")
        menu.addItem(withTitle: L("menuOpenConfig"), action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: L("menuAutostart"), action: #selector(toggleAgent), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menuQuit"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        contextMenu = menu
        // 왼쪽 클릭이면 창을 켜고/끄고, 오른쪽(또는 ⌃)클릭이면 메뉴를 띄운다.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func statusClicked() {
        let e = NSApp.currentEvent
        let isRight = e?.type == .rightMouseUp
            || e?.modifierFlags.contains(.control) == true
        if isRight {
            updateAgentCheck()
            if let button = statusItem.button {
                contextMenu.popUp(positioning: nil,
                                  at: NSPoint(x: 0, y: button.bounds.height + 4),
                                  in: button)
            }
        } else {
            togglePanel()
        }
    }

    // ── 창 ──
    func buildPanel() {
        let size = NSSize(width: 320, height: 460)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .fullSizeContentView,
                                    .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false   // 메뉴바에 붙어 나오므로 옮기지 않는다

        // 유리판처럼 뒤가 은근히 비치는 배경 + 그 위에 색을 살짝 덮어 팔레트를 유지한다
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.surface.withAlphaComponent(0.72).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])

        // 헤더
        let dot = NSView(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.backgroundColor = theme.accent.cgColor
        dot.layer?.cornerRadius = 3.5

        let title = label("Tally", size: 13, weight: .semibold, color: theme.ink)
        syncLabel = label("—", size: 10.5, weight: .regular, color: theme.mute, mono: true)

        let hairline = NSBox()
        hairline.boxType = .separator

        refreshButton = NSButton(title: "↻", target: self, action: #selector(fetchNow))
        refreshButton.isBordered = false
        refreshButton.contentTintColor = theme.accent
        refreshButton.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        refreshButton.toolTip = L("tipRefresh")

        searchField = NSSearchField()
        searchField.placeholderString = L("search")
        searchField.font = .systemFont(ofSize: 11.5)
        searchField.delegate = self
        searchField.focusRingType = .none

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.linkTextAttributes = [:]
        // 이 설정이 없으면 텍스트 컨테이너 폭이 0 이라 아무것도 안 보인다.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize =
            NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay      // 스크롤바가 폭을 차지하면 줄이 밀린다

        for v in [dot, title, syncLabel, refreshButton, hairline,
                  searchField, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            dot.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),

            refreshButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            syncLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            syncLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),

            hairline.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            hairline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            hairline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            searchField.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 7),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        // 위치는 저장하지 않는다 — 열 때마다 메뉴바 아이콘 아래로 붙인다.
    }

    func label(_ s: String, size: CGFloat, weight: NSFont.Weight,
               color: NSColor, mono: Bool = false) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight)
                      : .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        return f
    }

    /// 메뉴바 아이콘 바로 아래, 아이콘 가운데에 맞춰 붙인다.
    /// 화면 밖으로 나가지 않게 좌우로 밀어 넣는다.
    func anchorFrame(height: CGFloat) -> NSRect {
        let w: CGFloat = 320
        var iconRect: NSRect?
        if let button = statusItem.button, let bw = button.window {
            iconRect = bw.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screen = NSScreen.screens.first {
            guard let r = iconRect else { return false }
            return $0.frame.intersects(r)
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let h = max(160, min(height, vf.height * CGFloat(config.maxHeightPct / 100)))
        var x = (iconRect?.midX ?? vf.maxX - w - 16) - w / 2
        x = min(max(vf.minX + 8, x), vf.maxX - w - 8)
        let top = (iconRect?.minY ?? vf.maxY) - 4
        return NSRect(x: x, y: top - h, width: w, height: h)
    }

    /// 내용 높이에 맞춰 창을 줄이고 아이콘 아래로 붙인다.
    /// 창 폭이 바뀌면 오른쪽 정렬(개수)과 띠 배경이 어긋나므로 한 번 더 그린다.
    func fitAndAnchor() {
        guard !adjusting else { return }
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        adjusting = true
        lm.ensureLayout(for: tc)
        let textHeight = lm.usedRect(for: tc).height
        let chrome: CGFloat = 32 + 30 + 26      // 헤더 + 검색칸 + 여백
        panel.setFrame(anchorFrame(height: ceil(textHeight) + chrome), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        adjusting = false
        if abs(contentWidth() - lastRenderWidth) > 2 { render() }
    }

    /// 저장된 창 위치가 지금 붙어 있는 화면 밖이면(외부 모니터를 뽑은 경우 등)
    /// 오른쪽 위로 되돌린다. 안 그러면 창이 보이지 않는다.
    func frameIsVisible(_ f: NSRect) -> Bool {
        for screen in NSScreen.screens where screen.frame.intersects(f) {
            let overlap = screen.frame.intersection(f)
            if overlap.width > 80 && overlap.height > 60 { return true }
        }
        return false
    }

    /// 혹시 어긋났을 때 다시 아이콘 아래로 붙인다.
    @objc func resetPosition() {
        panel.orderFrontRegardless()
        render()
        fitAndAnchor()
    }

    // ── 데이터 읽기 ──
    func reload() {
        sections = buildSections()
        render()
        updateStatusTitle()
    }

    /// data.json + memo.txt 를 읽어 화면에 그릴 모델을 만든다(UI 손대지 않음).
    func buildSections() -> [Section] {
        var built: [Section] = []
        let raw = try? Data(contentsOf: dataURL)
        if raw == nil { log("data.json 읽기 실패: \(dataURL.path)") }
        if let d = raw,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let at = j["fetchedAt"] as? String {
                let fm = ISO8601DateFormatter()
                fetchedAt = fm.date(from: at)
            }
            fetchErrors = (j["errors"] as? [String]) ?? []
            for raw in (j["sections"] as? [[String: Any]]) ?? [] {
                var sec = Section()
                sec.key = raw["key"] as? String ?? ""
                sec.title = raw["title"] as? String ?? ""
                sec.hue = raw["hue"] as? String ?? "grey"
                if let items = raw["items"] as? [[String: Any]] {
                    sec.groups = [Group(key: "", title: "", rows: items.map(rowFrom))]
                }
                if let groups = raw["groups"] as? [[String: Any]] {
                    sec.groups = groups.map { g in
                        Group(key: g["title"] as? String ?? "",
                              title: g["title"] as? String ?? "",
                              color: g["color"] as? String ?? "plain",
                              rows: ((g["items"] as? [[String: Any]]) ?? []).map(rowFrom))
                    }
                }
                built.append(sec)
            }
            log("data.json OK — 칸 \(built.count)개 " +
                built.map { "\($0.key):\($0.count)" }.joined(separator: " "))
        } else if raw != nil {
            log("data.json 파싱 실패 (\(raw!.count) bytes)")
        }
        // 메모 칸은 파일에서 직접
        var memoRows: [Row] = []
        for (i, m) in loadMemos().enumerated() {
            var r = Row()
            r.kind = "memo"; r.index = i; r.title = m.title; r.detail = m.detail
            memoRows.append(r)
        }
        let memoSection = Section(key: "memo", title: config.memoTitle,
                                  hue: "amber", groups: [Group(rows: memoRows)])
        // Order comes from MW_SECTION_ORDER. "notes" means the local notes section;
        // any section the config does not mention is kept, at the end.
        var pool = built
        pool.append(memoSection)
        var ordered: [Section] = []
        for wanted in config.sectionOrder {
            let key = (wanted == "notes" || wanted == "memo") ? "memo" : wanted
            if let idx = pool.firstIndex(where: { $0.key == key }) {
                ordered.append(pool.remove(at: idx))
            }
        }
        ordered.append(contentsOf: pool)
        return ordered
    }

    /// Same content as text, for checking without opening the window (--dump)
    func dumpText() -> String {
        let secs = buildSections()
        var out: [String] = []
        if let at = fetchedAt {
            let mins = Int(Date().timeIntervalSince(at) / 60)
            out.append("Tally  ·  " + L("minsAgo", mins) + "  ·  ↻")
        } else {
            out.append("Tally  ·  " + L("never"))
        }
        out.append(String(repeating: "─", count: 46))
        for sec in secs {
            let folded = state.folded.contains(sec.key)
            out.append("▍\(folded ? "▸" : "▾") \(sec.title)\(String(repeating: " ", count: max(1, 30 - sec.title.count)))\(sec.count)")
            if folded { continue }
            for g in sec.groups {
                if !g.title.isEmpty {
                    let gf = state.folded.contains("\(sec.key)/\(g.key)")
                    out.append("   \(gf ? "▸" : "▾") \(g.title) \(g.rows.count)")
                    if gf { continue }
                }
                for r in g.rows {
                    if r.kind == "memo" {
                        let ex = state.expandedMemos.contains(r.title)
                        out.append("     ☐ \(ex ? "▾" : "▸") \(r.title)")
                        if ex && !r.detail.isEmpty { out.append("         \(r.detail)") }
                    } else {
                        var tail = ""
                        if !r.badge.isEmpty { tail = "  💬\(r.badge)" }
                        if !r.ci.isEmpty { tail += r.ci == "success" ? " ✓" : (r.ci == "failed" ? " ✗" : " ◐") }
                        else if r.ok && r.badge.isEmpty { tail += " ✓" }
                        let t = r.title.count > 32 ? String(r.title.prefix(32)) + "…" : r.title
                        out.append("     \(r.id)  \(t)\(tail)")
                    }
                }
            }
        }
        if !fetchErrors.isEmpty { out.append("\n! " + fetchErrors.joined(separator: " · ")) }
        return out.joined(separator: "\n")
    }

    func rowFrom(_ j: [String: Any]) -> Row {
        var r = Row()
        r.id = j["id"] as? String ?? ""
        r.title = j["title"] as? String ?? ""
        r.url = j["url"] as? String ?? ""
        r.badge = j["badge"] as? String ?? ""
        r.ok = j["ok"] as? Bool ?? false
        r.ci = (j["ci"] as? String) ?? (j["status"] as? String) ?? ""
        r.mine = j["mine"] as? Bool ?? false
        r.repo = j["repo"] as? String ?? ""
        r.repoFull = j["repoFull"] as? String ?? ""
        r.ref = j["ref"] as? String ?? ""
        r.ciUrl = j["ciUrl"] as? String ?? ""
        if let at = j["at"] as? String, !at.isEmpty {
            r.title += " · " + shortDate(at)
        }
        return r
    }

    func shortDate(_ iso: String) -> String {
        let fm = ISO8601DateFormatter()
        fm.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = fm.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return "" }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 2 { return L("justNow") }
        if mins < 60 { return L("minsAgo", mins) }
        if mins < 60 * 24 { return L("hoursAgo", mins / 60) }
        let f = DateFormatter(); f.dateFormat = L("dateFormat")
        return f.string(from: d)
    }

    // ── 검색 매칭 ──
    func matches(_ r: Row) -> Bool {
        if query.isEmpty { return true }
        let q = query.precomposedStringWithCanonicalMapping.lowercased()
        let hay = (r.id + " " + r.title).precomposedStringWithCanonicalMapping.lowercased()
        return hay.contains(q)
    }

    func visibleRows(_ g: Group) -> [Row] { g.rows.filter(matches) }

    // ── 그리기 ──
    func render() {
        let out = NSMutableAttributedString()
        let width = contentWidth()
        lastRenderWidth = width

        for sec in sections {
            let filtered = sec.groups.map { visibleRows($0) }.reduce(0) { $0 + $1.count }
            let folded = state.folded.contains(sec.key) && query.isEmpty
            out.append(bandLine(sec, count: filtered, total: sec.count,
                                folded: folded, width: width))
            if folded { continue }

            for g in sec.groups {
                let rows = visibleRows(g)
                if !g.title.isEmpty {
                    let gkey = "\(sec.key)/\(g.key)"
                    let gfolded = state.folded.contains(gkey) && query.isEmpty
                    out.append(groupLine(g, count: rows.count, total: g.rows.count,
                                         folded: gfolded, key: gkey, hue: sec.hue, width: width))
                    if gfolded { continue }
                }
                if rows.isEmpty && !query.isEmpty {
                    out.append(plain("      " + L("noMatches") + "\n", color: theme.mute, size: 10.5, italic: true))
                    continue
                }
                let gc = g.title.isEmpty ? nil : groupColor(g.color)
                let key = "\(sec.key)/\(g.key)"
                let cap = config.rowsPerSection
                let capped = cap > 0 && query.isEmpty && !state.showAll.contains(key)
                    && rows.count > cap
                let shown = capped ? Array(rows.prefix(cap)) : rows
                for r in shown { out.append(rowLine(r, sec: sec, width: width, idColor: gc)) }
                if capped {
                    out.append(moreLine(rows.count - cap, key: key,
                                        color: gc ?? theme.mute, width: width))
                } else if cap > 0 && query.isEmpty && state.showAll.contains(key)
                            && rows.count > cap {
                    out.append(lessLine(key: key, color: gc ?? theme.mute, width: width))
                }
            }
            // 메모 칸 끝에 추가 버튼
            if sec.key == "memo" && query.isEmpty {
                out.append(addMemoLine(width: width))
            }
        }

        if !fetchErrors.isEmpty {
            out.append(plain("\n  " + fetchErrors.joined(separator: " · ") + "\n",
                             color: theme.danger, size: 10))
        }
        textView.textStorage?.setAttributedString(out)
        updateSync()
        if panel != nil && panel.isVisible { fitAndAnchor() }
    }

    /// 주어진 폭에 들어가도록 제목을 줄인다. 잘림(truncation)에 맡기면
    /// 오른쪽에 붙인 개수·CI 표시까지 같이 사라진다.
    func fit(_ text: String, _ attrs: [NSAttributedString.Key: Any],
             into limit: CGFloat) -> String {
        func width(_ s: String) -> CGFloat {
            NSAttributedString(string: s, attributes: attrs).size().width
        }
        if limit <= 0 || width(text) <= limit { return text }
        let chars = Array(text)
        var lo = 0, hi = chars.count
        while lo < hi {                       // 이분 탐색으로 들어갈 길이를 찾는다
            let mid = (lo + hi + 1) / 2
            if width(String(chars[0..<mid]) + "…") <= limit { lo = mid } else { hi = mid - 1 }
        }
        return lo <= 0 ? "…" : String(chars[0..<lo]) + "…"
    }

    /// 오른쪽 정렬 탭 위치. 창 크기가 바뀌면 이 값도 따라가야 줄이 안 깨진다.
    func contentWidth() -> CGFloat {
        let container = textView.textContainer?.containerSize.width ?? textView.bounds.width
        let padding = (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let inset = textView.textContainerInset.width * 2
        return max(170, container - padding - inset - 4)
    }

    func para(width: CGFloat, indent: CGFloat) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .right, location: width)]
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.lineSpacing = 2.5
        p.paragraphSpacing = 1
        p.lineBreakMode = .byTruncatingTail
        p.tighteningFactorForTruncation = 0
        return p
    }

    func bandLine(_ sec: Section, count: Int, total: Int,
                  folded: Bool, width: CGFloat) -> NSAttributedString {
        let (bg, rail) = theme.hues[sec.hue] ?? (theme.head, theme.mute)
        let s = NSMutableAttributedString()
        let p = para(width: width, indent: 0)
        p.paragraphSpacingBefore = 7

        s.append(NSAttributedString(string: "▎", attributes: [
            .foregroundColor: rail, .backgroundColor: bg,
            .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: p,
        ]))
        let arrow = folded ? "▸" : "▾"
        s.append(NSAttributedString(string: " \(arrow)  \(sec.title)", attributes: [
            .foregroundColor: theme.ink, .backgroundColor: bg,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .kern: 0.2,
            .paragraphStyle: p, .link: "tally://fold/\(sec.key)",
        ]))
        let countText = (!query.isEmpty && count != total) ? "\(count)/\(total)" : "\(total)"
        s.append(NSAttributedString(string: "\t\(countText)  ", attributes: [
            .foregroundColor: rail, .backgroundColor: bg,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .paragraphStyle: p,
        ]))
        s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
        return s
    }

    func groupLine(_ g: Group, count: Int, total: Int, folded: Bool,
                   key: String, hue: String, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: 16)
        p.paragraphSpacingBefore = 5
        let color = groupColor(g.color)
        let arrow = folded ? "▸" : "▾"
        let countText = (!query.isEmpty && count != total) ? "\(count) / \(total)" : "\(total)"
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "  ", attributes: [.paragraphStyle: p]))
        s.append(NSAttributedString(string: "●", attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 7),
            .paragraphStyle: p, .link: "tally://fold/\(key)",
        ]))
        s.append(NSAttributedString(string: " \(arrow) \(g.title)", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .paragraphStyle: p, .link: "tally://fold/\(key)",
        ]))
        s.append(NSAttributedString(string: "\t\(countText)\n", attributes: [
            .foregroundColor: color.withAlphaComponent(0.75),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .paragraphStyle: p,
        ]))
        return s
    }

    func rowLine(_ r: Row, sec: Section, width: CGFloat,
                 idColor: NSColor? = nil) -> NSAttributedString {
        let p = para(width: width, indent: 20)
        let s = NSMutableAttributedString()
        let (_, hueRail) = theme.hues[sec.hue] ?? (theme.head, theme.mute)
        let rail = idColor ?? hueRail

        if r.kind == "memo" {
            let expanded = state.expandedMemos.contains(r.title)
            let tip = r.detail.isEmpty ? r.title : r.title + " — " + r.detail
            s.append(NSAttributedString(string: "  ", attributes: [.paragraphStyle: p]))
            s.append(NSAttributedString(string: "○", attributes: [
                .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: p, .link: "tally://memo-done/\(r.index)",
                .toolTip: L("tipDone"),
            ]))
            s.append(NSAttributedString(string: " ", attributes: [.paragraphStyle: p]))
            let memoAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.ink, .font: NSFont.systemFont(ofSize: 11.5),
                .paragraphStyle: p, .link: "tally://memo-toggle/\(r.index)",
                .toolTip: tip,
            ]
            s.append(NSAttributedString(
                string: (expanded ? "▾ " : "▸ ") + fit(r.title, memoAttrs, into: width - 62),
                attributes: memoAttrs))
            if expanded {
                s.append(NSAttributedString(string: "  ✎", attributes: [
                    .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: 10),
                    .paragraphStyle: p, .link: "tally://memo-edit/\(r.index)",
                    .toolTip: L("tipEdit"),
                ]))
            }
            s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
            if expanded && r.detail.isEmpty {
                let dp = para(width: width, indent: 34)
                s.append(NSAttributedString(string: L("writeDetail") + "\n", attributes: [
                    .foregroundColor: theme.mute,
                    .font: NSFont.systemFont(ofSize: 10.5),
                    .paragraphStyle: dp, .link: "tally://memo-edit/\(r.index)",
                ]))
            }
            if expanded && !r.detail.isEmpty {
                let dp = para(width: width, indent: 34)
                dp.lineBreakMode = .byWordWrapping
                s.append(NSAttributedString(string: r.detail + "\n", attributes: [
                    .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: 10.5),
                    .paragraphStyle: dp,
                ]))
            }
            return s
        }

        let link = r.url.isEmpty ? nil : r.url
        // 마우스를 올리면 잘린 제목 전체가 보이도록
        let tip = [r.repoFull.isEmpty ? r.repo : r.repoFull, r.id, r.title]
            .filter { !$0.isEmpty }.joined(separator: "  ")

        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: rail,
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
            .paragraphStyle: p, .toolTip: tip,
        ]
        if let link { attrs[.link] = link }
        s.append(NSAttributedString(string: "  " + r.id, attributes: attrs))

        if !r.repo.isEmpty {
            var repoAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.mute,
                .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
                .paragraphStyle: p, .toolTip: tip,
            ]
            if let link { repoAttrs[.link] = link }
            s.append(NSAttributedString(string: " " + r.repo, attributes: repoAttrs))
        }

        var titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.ink, .font: NSFont.systemFont(ofSize: 11.5),
            .paragraphStyle: p, .toolTip: tip,
        ]
        if let link { titleAttrs[.link] = link }
        // 오른쪽 표시(개수·CI)가 살아남도록 제목을 먼저 줄인다
        let used = s.size().width
        let tailRoom: CGFloat = r.badge.isEmpty ? 22 : CGFloat(24 + r.badge.count * 7)
        let room = width - used - tailRoom - 18
        s.append(NSAttributedString(string: " " + fit(r.title, titleAttrs, into: room),
                                    attributes: titleAttrs))

        // 오른쪽 표시: 코멘트 수 → CI → 리뷰 해결
        if !r.badge.isEmpty {
            // 안 읽은 코멘트 수 — 배경을 깔아 알약처럼
            s.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: p]))
            s.append(NSAttributedString(string: " \(r.badge) ", attributes: [
                .foregroundColor: theme.badge, .backgroundColor: theme.badgeBg,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .paragraphStyle: p,
            ]))
        } else {
            var tail = ""
            var tailColor = theme.mute
            if !r.ci.isEmpty {
                switch r.ci {
                case "success": tail = "✓"; tailColor = theme.accent
                case "failed", "canceled": tail = "✗"; tailColor = theme.danger
                case "running", "pending", "created": tail = "◍"; tailColor = theme.badge
                default: tail = "·"
                }
            } else if r.ok {
                tail = "✓"; tailColor = theme.accent
            }
            if !tail.isEmpty {
                s.append(NSAttributedString(string: "\t" + tail + " ", attributes: [
                    .foregroundColor: tailColor,
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .paragraphStyle: p,
                ]))
            }
        }
        // CI 뱃지가 코멘트 수에 밀린 MR 은 상태도 함께
        if !r.badge.isEmpty && !r.ci.isEmpty {
            let mark = r.ci == "success" ? " ✓" : (r.ci == "failed" ? " ✗" : " ◍")
            s.append(NSAttributedString(string: mark, attributes: [
                .foregroundColor: r.ci == "failed" ? theme.danger : theme.accent,
                .font: NSFont.systemFont(ofSize: 10), .paragraphStyle: p,
            ]))
        }
        s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
        return s
    }

    /// "+ 메모 추가" — 누르면 제목·상세를 함께 적는 창이 뜬다.
    func addMemoLine(width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: 20)
        p.paragraphSpacingBefore = 2
        return NSAttributedString(string: "  " + L("addMemo") + "\n", attributes: [
            .foregroundColor: theme.badge.withAlphaComponent(0.9),
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .paragraphStyle: p, .link: "tally://memo-add",
            .toolTip: L("tipAddMemo"),
        ])
    }

    /// "+7 더" — 누르면 그 묶음만 전부 펼친다.
    func moreLine(_ n: Int, key: String, color: NSColor, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: 20)
        return NSAttributedString(string: "  " + L("more", n) + "\n", attributes: [
            .foregroundColor: color.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .paragraphStyle: p, .link: "tally://more/\(key)",
            .toolTip: L("tipShowAll"),
        ])
    }

    func lessLine(key: String, color: NSColor, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: 20)
        return NSAttributedString(string: "  " + L("less") + "\n", attributes: [
            .foregroundColor: theme.mute,
            .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
            .paragraphStyle: p, .link: "tally://less/\(key)",
        ])
    }

    func plain(_ s: String, color: NSColor, size: CGFloat, italic: Bool = false) -> NSAttributedString {
        var font = NSFont.systemFont(ofSize: size)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return NSAttributedString(string: s, attributes: [.foregroundColor: color, .font: font])
    }

    // ── 링크 클릭 ──
    func textView(_ view: NSTextView, clickedOnLink link: Any, at index: Int) -> Bool {
        guard let s = (link as? String) ?? (link as? URL)?.absoluteString else { return false }
        if s.hasPrefix("tally://fold/") {
            let key = String(s.dropFirst("tally://fold/".count))
            if state.folded.contains(key) { state.folded.remove(key) } else { state.folded.insert(key) }
            state.save()
            render()
            DispatchQueue.main.async { [weak self] in self?.render() }
            return true
        }
        if s.hasPrefix("tally://memo-toggle/") {
            let i = Int(s.dropFirst("tally://memo-toggle/".count)) ?? -1
            let memos = loadMemos()
            if memos.indices.contains(i) {
                let t = memos[i].title
                if state.expandedMemos.contains(t) { state.expandedMemos.remove(t) }
                else { state.expandedMemos.insert(t) }
                state.save(); reload()
            }
            return true
        }
        if s.hasPrefix("tally://more/") {
            state.showAll.insert(String(s.dropFirst("tally://more/".count)))
            state.save(); render()
            return true
        }
        if s.hasPrefix("tally://less/") {
            state.showAll.remove(String(s.dropFirst("tally://less/".count)))
            state.save(); render()
            return true
        }
        if s == "tally://memo-add" {
            addMemo()
            return true
        }
        if s.hasPrefix("tally://memo-edit/") {
            let i = Int(s.dropFirst("tally://memo-edit/".count)) ?? -1
            editDetail(i)
            return true
        }
        if s.hasPrefix("tally://memo-done/") {
            let i = Int(s.dropFirst("tally://memo-done/".count)) ?? -1
            var memos = loadMemos()
            if memos.indices.contains(i) {
                let m = memos[i]
                archive(m)
                state.expandedMemos.remove(m.title)
                memos.remove(at: i)
                saveMemos(memos); state.save(); reload()
            }
            return true
        }
        if let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    /// 메모 추가 — 제목과 상세를 한 창에서 받는다.
    @objc func addMemo() {
        let alert = NSAlert()
        alert.messageText = L("addMemoTitle")
        alert.informativeText = L("addMemoInfo")
        alert.addButton(withTitle: L("add"))
        alert.addButton(withTitle: L("cancel"))

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 56))
        let titleField = NSTextField(frame: NSRect(x: 0, y: 30, width: 330, height: 24))
        titleField.placeholderString = L("titleField")
        let detailField = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        detailField.placeholderString = L("detailField")
        titleField.nextKeyView = detailField
        box.addSubview(titleField)
        box.addSubview(detailField)
        alert.accessoryView = box
        alert.window.initialFirstResponder = titleField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let t = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var memos = loadMemos()
        memos.append(Memo(title: t,
                          detail: detailField.stringValue.trimmingCharacters(in: .whitespaces)))
        saveMemos(memos)
        if !detailField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            state.expandedMemos.insert(t)
            state.save()
        }
        reload()
    }

    /// 메모 상세를 창에서 고친다.
    func editDetail(_ i: Int) {
        var memos = loadMemos()
        guard memos.indices.contains(i) else { return }
        let alert = NSAlert()
        alert.messageText = memos[i].title
        alert.informativeText = L("detailTitle")
        alert.addButton(withTitle: L("save"))
        alert.addButton(withTitle: L("cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = memos[i].detail
        field.placeholderString = L("detailHint")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            memos[i].detail = field.stringValue.trimmingCharacters(in: .whitespaces)
            saveMemos(memos)
            state.expandedMemos.insert(memos[i].title)
            state.save()
            reload()
        }
    }

    /// 실수로 완료한 메모를 되돌린다 — done.txt 의 마지막 항목을 되가져온다.
    @objc func undoDone() {
        guard let text = try? String(contentsOf: doneURL, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: .newlines)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        // 마지막 "[날짜] 제목" 줄을 찾고, 그 뒤 들여쓴 줄들을 상세로 본다
        guard let start = lines.lastIndex(where: { $0.hasPrefix("[") }) else {
            notify(L("nothingToUndo"), L("noFinished"))
            return
        }
        let block = lines[start...]
        var title = String(block.first ?? "")
        if let close = title.firstIndex(of: "]") {
            title = String(title[title.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
        }
        let detail = block.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        lines.removeSubrange(start..<lines.endIndex)
        try? lines.joined(separator: "\n").write(to: doneURL, atomically: true, encoding: .utf8)

        var memos = loadMemos()
        memos.append(Memo(title: title, detail: detail))
        saveMemos(memos)
        reload()
        notify(L("memoRestored"), title, subtitle: L("memoSection"))
    }

    /// 완료한 메모는 지우지 않고 done.txt 에 날짜와 함께 남긴다(실수로 눌러도 복구 가능).
    func archive(_ m: Memo) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        var line = "[\(f.string(from: Date()))] \(m.title)\n"
        if !m.detail.isEmpty { line += "    \(m.detail)\n" }
        if let h = try? FileHandle(forWritingTo: doneURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: doneURL, atomically: true, encoding: .utf8)
        }
    }

    // ── 검색 · 메모 입력 ──
    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSSearchField, f === searchField else { return }
        query = f.stringValue.trimmingCharacters(in: .whitespaces)
        render()
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            if control === searchField {
                searchField.stringValue = ""; query = ""; render(); return true
            }
        }
        return false
    }

    // ── 조회 ──
    @objc func fetchNow() { fetch() }

    func allCIRows() -> [Row] {
        let ci = sections.first(where: { $0.key == "ci" })?.groups.flatMap { $0.rows } ?? []
        let mr = sections.first(where: { $0.key == "code" })?.groups
            .flatMap { $0.rows }.filter { !$0.ci.isEmpty } ?? []
        return ci + mr
    }

    /// 평소엔 설정된 주기, 파이프라인이 돌고 있거나 방금 올렸으면 짧은 주기.
    func nextInterval() -> TimeInterval {
        let running = allCIRows().contains {
            ["running", "pending", "created"].contains($0.ci)
        }
        if running { return config.fastSeconds }
        if let u = fastUntil, u > Date() { return config.fastSeconds }
        return config.refreshHours * 3600
    }

    func scheduleNext() {
        timer?.invalidate()
        let interval = nextInterval()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
            [weak self] _ in self?.fetch()
        }
        log("다음 조회 \(Int(interval))초 후")
    }

    /// 내 파이프라인 + 내 MR 의 파이프라인. (배포 브랜치에서 남이 돌린 건 제외)
    func myCIRows() -> [(Row, Bool)] {
        var out: [(Row, Bool)] = []
        for r in sections.first(where: { $0.key == "ci" })?.groups.flatMap({ $0.rows }) ?? [] {
            out.append((r, r.mine))
        }
        for r in sections.first(where: { $0.key == "code" })?.groups
            .flatMap({ $0.rows }).filter({ !$0.ci.isEmpty }) ?? [] {
            out.append((r, true))       // 내가 올린 MR 이므로 항상 내 것
        }
        return out
    }

    /// 상태가 "바뀌는 순간" 만 알린다.
    /// 성공은 돌고 있던 것이 끝났을 때만 알린다 — 처음 켤 때 다 성공이라고 울리지 않게.
    func notifyCIChanges() {
        var now: [String: String] = [:]
        let mode = config.notifyCI
        for (r, mine) in myCIRows() {
            let key = r.url.isEmpty ? "\(r.id)/\(r.title)" : r.url
            now[key] = r.ci
            guard mode != "n", mine, let before = prevCI[key], before != r.ci else { continue }
            // 어느 프로젝트 · 어느 브랜치인지 부제목에, 무엇인지 본문에
            let project = r.repoFull.isEmpty ? r.repo : r.repoFull
            let branch = prettyRef(r.ref)
            let subtitle = [project, branch].filter { !$0.isEmpty }.joined(separator: "  ·  ")
            var body = r.title
            if r.id.hasPrefix("!") { body = "\(r.id)  \(r.title)" }
            if body.trimmingCharacters(in: .whitespaces).isEmpty { body = branch }
            if ["failed", "canceled"].contains(r.ci) {
                notify(L("ciFail"), body, subtitle: subtitle, sound: "Basso",
                       kind: .fail, url: r.ciUrl.isEmpty ? r.url : r.ciUrl)
            } else if r.ci == "success",
                      ["running", "pending", "created"].contains(before), mode == "all" {
                notify(L("ciOk"), body, subtitle: subtitle, sound: "Tink",
                       kind: .ok, url: r.ciUrl.isEmpty ? r.url : r.ciUrl)
            } else if ["running", "pending", "created"].contains(r.ci),
                      !["running", "pending", "created"].contains(before), mode == "all" {
                notify(L("ciRun"), body, subtitle: subtitle,
                       kind: .run, url: r.ciUrl.isEmpty ? r.url : r.ciUrl)
            }
        }
        prevCI = now
    }

    /// 알림을 앱이 직접 띄우도록 준비한다 — 배너 왼쪽에 우리 아이콘이 나오게.
    func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else {
            log("번들 아님 — 알림은 osascript 로")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, err in
            DispatchQueue.main.async {
                self?.canPostNative = granted && err == nil
                log(granted ? "시스템 알림 권한 있음(쓰지 않음 — 자체 배너 사용)"
                            : "시스템 알림 권한 없음 — 자체 배너 사용")
            }
        }
    }

    /// refs/merge-requests/293/head → MR !293, 그 외는 브랜치 이름 그대로
    func prettyRef(_ ref: String) -> String {
        if ref.hasPrefix("refs/merge-requests/") {
            let parts = ref.split(separator: "/")
            if parts.count > 2 { return "MR !\(parts[2])" }
        }
        return ref
    }

    func notify(_ title: String, _ body: String,
                subtitle: String? = nil, sound: String? = nil,
                kind: Banner.Kind = .info, url: String? = nil) {
        Banner.show(kind, title: title, subtitle: subtitle ?? "", body: body,
                    theme: theme, playSound: sound != nil) {
            if let url, let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
    }

    // ── 조회 실행 ──
    func fetch() {
        guard !fetching else { return }
        fetching = true
        refreshButton.title = "◌"
        refreshButton.contentTintColor = theme.mute
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [fetchURL.path]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                self.refreshButton.title = "↻"
                self.refreshButton.contentTintColor = self.theme.accent
                self.lastFetchOK = p.terminationStatus == 0
                self.reload()
                self.notifyCIChanges()
                self.scheduleNext()
            }
        }
    }

    /// 마지막 조회가 언제였는지. 실패했으면 그 사실을 분명히 적는다 —
    /// 사내망 밖에서 옛 데이터를 지금 것으로 오해하지 않도록.
    func updateSync() {
        guard let at = fetchedAt else { syncLabel.stringValue = L("never"); return }
        let mins = Int(Date().timeIntervalSince(at) / 60)
        var text: String
        if fetching { text = L("fetching") }
        else if mins < 2 { text = L("justNow") }
        else if mins < 60 { text = L("minsAgo", mins) }
        else if mins < 60 * 24 { text = L("hoursAgo", mins / 60) }
        else { text = L("daysAgo", mins / 1440) }
        let stale = mins > Int(config.refreshHours * 60) * 2
        if !lastFetchOK { text = L("failedPrefix") + text + L("staleSuffix") }
        syncLabel.stringValue = text
        syncLabel.textColor = (!lastFetchOK || stale) ? theme.danger : theme.mute
    }

    /// 메뉴바 색은 맥이 밝기에 맞춰 조절해 주는 시스템 색을 쓴다.
    /// 직접 hex 를 넣으면 밝은 메뉴바나 어두운 메뉴바 한쪽에서 반드시 묻힌다.
    struct BarPalette {
        let mr = NSColor.systemTeal
        let issue = NSColor.systemBlue
        let memo = NSColor.systemOrange
        let ok = NSColor.systemGreen
        let bad = NSColor.systemRed
        let run = NSColor.systemOrange
    }

    var barPalette: BarPalette { BarPalette() }

    func updateStatusTitle() {
        log("메뉴바 갱신 — " + sections.map { "\($0.key):\($0.count)" }.joined(separator: " "))

        let pal = barPalette
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let out = NSMutableAttributedString()
        func add(_ text: String, _ color: NSColor, weight: NSFont.Weight = .semibold) {
            out.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: weight),
            ]))
        }
        func sep() {
            if out.length > 0 {
                out.append(NSAttributedString(string: " · ", attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular),
                ]))
            }
        }

        for sec in sections where sec.count > 0 {
            switch sec.key {
            case "code": sep(); add("\(sec.count) \(sec.title)", pal.mr)
            case "issues": sep(); add("\(sec.count) \(sec.title)", pal.issue)
            case "memo": sep(); add("\(sec.count) \(sec.title)", pal.memo)
            case "ci": break                       // CI is summarised below
            default: sep(); add("\(sec.count) \(sec.title)", .labelColor)
            }
        }

        let all = myCIRows()
        let running = all.filter { ["running", "pending", "created"].contains($0.0.ci) }
        let failed = all.filter { ["failed", "canceled"].contains($0.0.ci) }
        if !running.isEmpty {
            sep(); add(running.count > 1 ? "CI ◍\(running.count)" : "CI ◍", pal.run)
        } else if !failed.isEmpty {
            sep(); add(failed.count > 1 ? "CI ✗\(failed.count)" : "CI ✗", pal.bad, weight: .bold)
        } else if !all.isEmpty {
            sep(); add("CI ✓", pal.ok)
        }

        if out.length == 0 { add("Tally", .labelColor) }
        statusItem.button?.font = font
        statusItem.button?.attributedTitle = out
    }

    // ── 메뉴 동작 ──
    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            state.open = false
        } else {
            showPanel()
            state.open = true
        }
        state.save()
        updateAgentCheck()
    }

    func showPanel() {
        panel.setFrame(anchorFrame(height: max(panel.frame.height, 320)), display: false)
        panel.orderFrontRegardless()
        // 먼저 레이아웃을 확정해야 글자 폭이 제대로 잡힌다 —
        // 이 순서를 놓치면 처음 열 때 줄이 어긋나 보인다.
        panel.contentView?.layoutSubtreeIfNeeded()
        render()
        fitAndAnchor()
        updateAgentCheck()
        // 한 프레임 뒤 실제 폭으로 한 번 더 (스크롤바 등장 등으로 폭이 바뀔 수 있다)
        DispatchQueue.main.async { [weak self] in
            self?.render()
            self?.fitAndAnchor()
        }
    }

    @objc func openMemo() { NSWorkspace.shared.open(memoURL) }
    @objc func openConfig() { NSWorkspace.shared.open(configURL) }
    @objc func openDone() {
        if !FileManager.default.fileExists(atPath: doneURL.path) {
            try? "".write(to: doneURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(doneURL)
    }
    @objc func quit() { NSApp.terminate(nil) }

    /// 로그인할 때 자동으로 뜨도록 LaunchAgent 를 켜고/끈다.
    @objc func toggleAgent() {
        if FileManager.default.fileExists(atPath: agentURL.path) {
            _ = shell("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentID)"])
            try? FileManager.default.removeItem(at: agentURL)
        } else {
            let exe = dir.appendingPathComponent("Tally.app/Contents/MacOS/tally").path
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(agentID)</string>
              <key>ProgramArguments</key><array><string>\(exe)</string></array>
              <key>EnvironmentVariables</key>
              <dict>
                <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
              </dict>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key>
              <dict><key>SuccessfulExit</key><false/></dict>
              <key>ProcessType</key><string>Interactive</string>
              <key>LimitLoadToSessionType</key><string>Aqua</string>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: agentURL, atomically: true, encoding: .utf8)
            _ = shell("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
        }
        updateAgentCheck()
    }

    func updateAgentCheck() {
        let on = FileManager.default.fileExists(atPath: agentURL.path)
        contextMenu?.items.first { $0.title == L("menuAutostart") }?.state = on ? .on : .off
        contextMenu?.items.first { $0.title == L("menuShow") }?.state =
            panel?.isVisible == true ? .on : .off
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound, .list])
    }

    func shell(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
}

// ─────────────────────────────── 실행 ───────────────────────────────

/// 같은 위젯이 이미 돌고 있으면 조용히 종료한다(LaunchAgent 와 수동 실행이 겹치는 경우).
func claimSingleInstance() {
    let lock = dir.appendingPathComponent(".lock")
    let fd = open(lock.path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { return }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        FileHandle.standardError.write("Tally is already running.\n".data(using: .utf8)!)
        exit(0)
    }
    // fd 를 닫지 않고 프로세스가 사는 동안 유지 → 종료 시 자동 해제
}

if CommandLine.arguments.contains("--notify-test") {
    // Shows one banner of each kind so you can check colours and sounds.
    let app = NSApplication.shared
    let w = Widget()
    app.delegate = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        w.notify(L("ciFail"), "!42  fix: retry policy on timeout",
                 subtitle: "api  ·  fix/timeout", sound: "Basso", kind: .fail)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        w.notify(L("ciOk"), "#17  refactor: split the fetch layer",
                 subtitle: "web  ·  PR #17", sound: "Tink", kind: .ok)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        w.notify(L("ciRun"), "!43  add index on created_at",
                 subtitle: "api  ·  perf/index", kind: .run)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 11) { exit(0) }
    app.run()
}

if CommandLine.arguments.contains("--dump") {
    let w = Widget()
    Strings.lang = w.config.lang        // --dump also honours MW_LANG
    // fetchedAt 만 읽어 오기 위해 data.json 을 먼저 훑는다
    if let d = try? Data(contentsOf: dataURL),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        if let at = j["fetchedAt"] as? String { w.fetchedAt = ISO8601DateFormatter().date(from: at) }
        w.fetchErrors = (j["errors"] as? [String]) ?? []
    }
    print(w.dumpText())
    exit(0)
}

claimSingleInstance()

let app = NSApplication.shared
let widget = Widget()
app.delegate = widget
app.run()
