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
let alarmURL = dir.appendingPathComponent("alarm.txt")
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
        "menuLook":      ["en": "Appearance",        "ko": "보기 설정"],
        "menuOpenAlarm": ["en": "Open alarms file",  "ko": "알림 파일 열기"],
        "alarmRang":     ["en": "Alarm",             "ko": "알림"],
        "addAlarm":      ["en": "+ Add alarm",       "ko": "+ 알림 추가"],
        "addAlarmTitle": ["en": "New alarm",         "ko": "알림 추가"],
        "editAlarmTitle":["en": "Edit alarm",        "ko": "알림 고치기"],
        "alarmHelp":     ["en": "When: daily 18:00 · mon,wed,fri 09:30 · fri 17:00 · 1st 10:00 · 08-25 14:00",
                          "ko": "일정: 매일 18:00 · 월,수,금 09:30 · 금 17:00 · 1일 10:00 · 08-25 14:00"],
        "alarmWhen":     ["en": "When (e.g. daily 18:00)", "ko": "일정 (예: 매일 18:00)"],
        "alarmWhat":     ["en": "What to say",       "ko": "알릴 내용"],
        "alarmBad":      ["en": "Could not read that schedule.", "ko": "일정을 못 읽었습니다."],
        "tipAlarmOff":   ["en": "Turn this alarm off", "ko": "이 알림 끄기"],
        "tipAlarmEdit":  ["en": "Edit this alarm",    "ko": "이 알림 고치기"],
        "tipAlarmAdd":   ["en": "Add an alarm",       "ko": "알림 추가"],
        "alarmToday":    ["en": "today",             "ko": "오늘"],
        "alarmTomorrow": ["en": "tomorrow",          "ko": "내일"],
        "alarmYesterday":["en": "yesterday",         "ko": "어제"],
        "delete":        ["en": "Delete",            "ko": "삭제"],
        "alarmTime":     ["en": "Time",               "ko": "시각"],
        "alarmRepeat":   ["en": "Repeat",             "ko": "반복"],
        "everyDay":      ["en": "Every day",          "ko": "매일"],
        "everyWeek":     ["en": "Weekly",             "ko": "매주"],
        "everyMonth":    ["en": "Monthly",            "ko": "매월"],
        "everyOnce":     ["en": "Once",               "ko": "한 번"],
        "alarmSound":    ["en": "Sound",              "ko": "소리"],
        "soundDefault":  ["en": "Default",            "ko": "기본"],
        "soundNone":     ["en": "Silent",             "ko": "무음"],
        "soundPlay":     ["en": "Play",               "ko": "들어보기"],
        "alarmSnooze":   ["en": "Remind me again in 10 min", "ko": "10분 뒤 다시 알림"],
        "snoozeNow":     ["en": "Again in 10 min",    "ko": "10분 뒤 다시"],
        "needWeekday":   ["en": "Pick at least one day.", "ko": "요일을 하나는 골라주세요."],
        "dayOfMonth":    ["en": "day",                "ko": "일"],
        "tipAlarmOn":    ["en": "Turn this alarm on or off", "ko": "이 알림 켜기·끄기"],
        "lookNow":       ["en": "now",               "ko": "지금"],
        "lookText":      ["en": "Text",              "ko": "글자"],
        "lookLine":      ["en": "Line gap",          "ko": "줄 간격"],
        "lookRow":       ["en": "Item gap",          "ko": "항목 간격"],
        "lookHead":      ["en": "Section titles",    "ko": "칸 제목"],
        "lookWidth":     ["en": "Window width",      "ko": "창 폭"],
        "lookBigger":    ["en": "bigger",            "ko": "크게"],
        "lookSmaller":   ["en": "smaller",           "ko": "작게"],
        "lookWider":     ["en": "wider",             "ko": "넓게"],
        "lookNarrower":  ["en": "narrower",          "ko": "좁게"],
        "lookHover":     ["en": "Highlight row under mouse", "ko": "올린 줄 강조"],
        "lookHoverUp":   ["en": "Highlight stronger", "ko": "강조 진하게"],
        "lookHoverDown": ["en": "Highlight softer",   "ko": "강조 연하게"],
        "lookReset":     ["en": "Back to config file values", "ko": "설정 파일 값으로 되돌리기"],
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
        // 다 비었을 때 메뉴바에 뜨는 말. 조회가 성공했을 때만 쓴다 —
        // 조회 실패로 비어 있는 걸 "다 끝냈다"고 말하면 거짓말이 된다.
        "allClear":      ["en": "All clear",         "ko": "All clear"],
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
                "rose": (rgb("#4A3540"), rgb("#DE9AA8")),
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

// ─────────────────────── 글자 크기·행간 ───────────────────────

/// 글자 크기와 여백의 배율. config.sh 의 MW_FONT_SCALE / MW_LINE_SPACING /
/// MW_ROW_GAP 으로 조절한다. Config.load() 가 읽어서 여기에 넣는다.
/// 메뉴바 글자와 알림 배너는 배율을 받지 않는다 — 메뉴바 높이는 시스템이 정하고
/// 배너는 폭이 고정이라 키우면 글자가 잘린다.
enum Metrics {
    static var fontScale: CGFloat = 1.0
    static var lineSpacing: CGFloat = 2.5
    static var rowGap: CGFloat = 1.0
    /// 칸 제목(MR·이슈·메모·CI) 크기. MW_FONT_SCALE 을 받지 않는다 — MW_HEAD_SIZE 로만 바꾼다.
    static var headSize: CGFloat = 12.5
    static var headCountSize: CGFloat { headSize - 1.5 }   // 제목 옆 개수
    static var headRailSize: CGFloat { headSize + 0.5 }    // 왼쪽 색 띠 ▎
}

/// 배율을 먹인 크기. 0.5 단위로 맞춰 글자가 흐려지는 것을 막는다.
func fs(_ size: CGFloat) -> CGFloat { (size * Metrics.fontScale * 2).rounded() / 2 }

/// 왼쪽 들여쓰기 기준. 칸마다 선행 공백으로 밀면 안 된다 — 공백 폭이 글자 크기·
/// 폰트(모노/시스템)마다 달라서 MR·이슈·메모·CI 의 앞이 서로 어긋난다.
/// 오프셋은 전부 여기 값 하나로만 주고, 배율에 따라 같이 커진다.
enum Indent {
    static var group: CGFloat { fs(18) }    // 묶음 제목 (● ▾ In Progress)
    static var row: CGFloat { fs(28) }      // 항목 줄 · + 메모 추가 · +N개 더
    static var detail: CGFloat { fs(42) }   // 메모 상세
}

// ─────────────────────────────── 설정 ───────────────────────────────

struct Config {
    var theme = "titanium"
    var refreshHours = 4.0
    var foldedDefault: Set<String> = ["plane"]
    var fastSeconds = 120.0
    var watchDirs: [String] = []
    var notifyCI = "all"        // all | fail | n
    var soundOK = "Tink"        // 시스템 소리 이름, 파일 경로, 또는 빈 값(무음)
    var soundFail = "Basso"
    var soundRun = ""
    var maxHeightPct = 55.0
    var rowsPerSection = 8
    var fontScale = 1.0        // 본문 글자 배율 (1.0 = 원래 크기)
    var lineSpacing = 2.5      // 줄 사이 여백
    var rowGap = 1.0           // 항목 사이 여백
    var width = 320.0          // 창 폭. 글자를 키우면 같이 넓혀야 제목이 안 잘린다
    var headSize = 12.5        // 칸 제목 크기 (배율과 별개)
    var hover = true           // 마우스 올린 줄에 배경색
    var hoverStrength = 60.0   // 그 배경이 얼마나 진한지 (0~100)
    var mrLabel = "branch"     // branch | number — MR 줄 맨 앞에 무엇을 쓸지
    var alarmTitle = "Alarms"
    var soundAlarm = "Ping"    // 알림 소리 (CI 소리와 구분되게 따로 둔다)
    var alarmGrace = 12.0      // 놓친 알림을 몇 시간까지 살려둘지
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
            case "MW_SOUND_OK": c.soundOK = val
            case "MW_SOUND_FAIL": c.soundFail = val
            case "MW_SOUND_RUN": c.soundRun = val
            case "MW_MAX_HEIGHT_PCT": c.maxHeightPct = Double(val) ?? 55
            case "MW_ROWS_PER_SECTION": c.rowsPerSection = Int(val) ?? 8
            case "MW_FONT_SCALE": c.fontScale = min(max(Double(val) ?? 1, 0.8), 1.6)
            case "MW_LINE_SPACING": c.lineSpacing = min(max(Double(val) ?? 2.5, 0), 14)
            case "MW_ROW_GAP": c.rowGap = min(max(Double(val) ?? 1, 0), 14)
            case "MW_WIDTH": c.width = min(max(Double(val) ?? 320, 260), 560)
            case "MW_HEAD_SIZE": c.headSize = min(max(Double(val) ?? 12.5, 9), 20)
            case "MW_HOVER": c.hover = !["n", "no", "0", "false"].contains(val.lowercased())
            case "MW_HOVER_STRENGTH": c.hoverStrength = min(max(Double(val) ?? 60, 0), 100)
            case "MW_MR_LABEL": c.mrLabel = val.lowercased() == "number" ? "number" : "branch"
            case "MW_LANG": c.lang = val.lowercased() == "ko" ? "ko" : "en"
            case "MW_TITLE_MEMO": c.memoTitle = val
            case "MW_TITLE_ALARM": c.alarmTitle = val
            case "MW_SOUND_ALARM": c.soundAlarm = val
            case "MW_ALARM_GRACE_HOURS": c.alarmGrace = min(max(Double(val) ?? 12, 0), 72)
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
        Metrics.fontScale = CGFloat(c.fontScale)
        Metrics.lineSpacing = CGFloat(c.lineSpacing)
        Metrics.rowGap = CGFloat(c.rowGap)
        Metrics.headSize = CGFloat(c.headSize)
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
    var index = 0        // 메모·알림 순번
    var pending = false  // 울렸는데 아직 안 끈 알림
    var on = true        // 알림이 켜져 있나
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

// ────────────────────────────── 알림 ──────────────────────────────

/// alarm.txt 한 줄 = 알림 하나. `<일정> <HH:MM>  <알릴 내용>`
///
///     매일 18:00       타임시트 쓰기
///     월,수,금 09:30   스탠드업
///     금 17:00         주간회고
///     1일 10:00        경비 정산
///     08-25 14:00      치과            (매년)
///     2026-08-25 14:00 치과            (한 번만)
///
/// 정시에 울려야 하므로 조회(fetch.py)가 아니라 위젯이 직접 읽고 계산한다.
struct Alarm {
    enum Every { case day, week, month, year, once }
    var line = ""            // 원본 줄 — 상태(끔·울림) 저장 키
    var src = 0              // 파일에서 몇 번째 줄인지 (고칠 때 쓴다)
    var title = ""
    var every: Every = .day
    var weekdays: Set<Int> = []   // 1=일 … 7=토 (Calendar 기준)
    var day = 0, month = 0, year = 0
    var hour = 0, minute = 0
    var on = true            // 아이폰처럼, 지우지 않고 잠시 꺼둘 수 있다
    var sound = ""           // 빈 값 = MW_SOUND_ALARM, "none" = 무음
    var snooze = 0           // 다시 알림(분). 0 이면 안 씀
}

/// 알림 창에서 고른 값 → alarm.txt 한 줄. 사람이 읽을 수 있게 쓴다.
func alarmLine(_ a: Alarm) -> String {
    let ko = Strings.lang == "ko"
    var spec = ""
    switch a.every {
    case .day: spec = ko ? "매일" : "daily"
    case .week:
        let names = ko ? ["일","월","화","수","목","금","토"]
                       : ["sun","mon","tue","wed","thu","fri","sat"]
        spec = a.weekdays.sorted().map { names[$0 - 1] }.joined(separator: ",")
    case .month: spec = ko ? "\(a.day)일" : "\(a.day)th"
    case .year: spec = String(format: "%02d-%02d", a.month, a.day)
    case .once: spec = String(format: "%04d-%02d-%02d", a.year, a.month, a.day)
    }
    var out = a.on ? "" : "off "
    out += String(format: "%@ %02d:%02d  %@", spec, a.hour, a.minute, a.title)
    if !a.sound.isEmpty { out += " sound=\(a.sound)" }
    if a.snooze > 0 { out += " snooze=\(a.snooze)" }
    return out
}

/// 요일 이름 → Calendar 의 weekday. 한글은 첫 글자만 본다.
private let weekdayNames: [String: Int] = [
    "일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7,
    "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
]

/// 못 읽는 줄은 nil. 사람이 손으로 고치는 파일이라 조용히 넘긴다(로그만).
func parseAlarm(_ raw: String, src: Int) -> Alarm? {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty || line.hasPrefix("#") { return nil }
    var body = line
    var on = true
    for off in ["off ", "OFF ", "Off "] where body.hasPrefix(off) {
        on = false
        body = String(body.dropFirst(off.count))
    }
    var parts = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    // 뒤에 붙는 설정 토큰을 먼저 떼어낸다 — 남은 것이 알릴 내용이다
    var sound = "", snooze = 0
    parts = parts.filter { token in
        if token.hasPrefix("sound=") { sound = String(token.dropFirst(6)); return false }
        if token.hasPrefix("snooze=") { snooze = Int(token.dropFirst(7)) ?? 0; return false }
        return true
    }
    guard parts.count >= 3 else { return nil }

    // 시각
    let hm = parts[1].split(separator: ":").map { Int($0) ?? -1 }
    guard hm.count == 2, hm[0] >= 0, hm[0] < 24, hm[1] >= 0, hm[1] < 60 else { return nil }

    var a = Alarm()
    a.line = line
    a.src = src
    a.hour = hm[0]
    a.minute = hm[1]
    a.title = parts[2...].joined(separator: " ")
    a.on = on
    a.sound = sound
    a.snooze = max(0, min(snooze, 180))

    let spec = parts[0]
    let low = spec.lowercased()
    if ["매일", "daily", "everyday", "every"].contains(low) {
        a.every = .day
    } else if spec.contains("-") {
        let d = spec.split(separator: "-").map { Int($0) ?? -1 }
        if d.count == 2, d[0] >= 1, d[0] <= 12, d[1] >= 1, d[1] <= 31 {
            a.every = .year; a.month = d[0]; a.day = d[1]        // 매년
        } else if d.count == 3, d[0] > 1900, d[1] >= 1, d[1] <= 12, d[2] >= 1, d[2] <= 31 {
            a.every = .once; a.year = d[0]; a.month = d[1]; a.day = d[2]
        } else { return nil }
    } else if let n = Int(low.replacingOccurrences(of: "일", with: "")
                             .replacingOccurrences(of: "st", with: "")
                             .replacingOccurrences(of: "nd", with: "")
                             .replacingOccurrences(of: "rd", with: "")
                             .replacingOccurrences(of: "th", with: "")),
              n >= 1, n <= 31 {
        a.every = .month; a.day = n                              // 매월 며칠
    } else {
        for token in low.split(separator: ",") {
            let t = String(token)
            if let w = weekdayNames[t] ?? weekdayNames[String(t.prefix(3))]
                ?? weekdayNames[String(t.prefix(1))] { a.weekdays.insert(w) }
        }
        guard !a.weekdays.isEmpty else { return nil }
        a.every = .week
    }
    return a
}

func loadAlarmLines() -> [String] {
    guard let text = try? String(contentsOf: alarmURL, encoding: .utf8) else { return [] }
    return text.components(separatedBy: .newlines)
}

func loadAlarms() -> [Alarm] {
    loadAlarmLines().enumerated().compactMap { parseAlarm($0.element, src: $0.offset) }
}

func saveAlarmLines(_ lines: [String]) {
    var out = lines
    while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
    try? (out.joined(separator: "\n") + "\n")
        .write(to: alarmURL, atomically: true, encoding: .utf8)
}

/// 그 날짜에 이 알림이 울리나? 울리면 그 시각.
func alarmOccurrence(_ a: Alarm, onDay day: Date, _ cal: Calendar) -> Date? {
    let c = cal.dateComponents([.year, .month, .day, .weekday], from: day)
    switch a.every {
    case .day: break
    case .week: guard a.weekdays.contains(c.weekday ?? 0) else { return nil }
    case .month: guard c.day == a.day else { return nil }
    case .year: guard c.month == a.month, c.day == a.day else { return nil }
    case .once: guard c.year == a.year, c.month == a.month, c.day == a.day else { return nil }
    }
    return cal.date(bySettingHour: a.hour, minute: a.minute, second: 0, of: day)
}

/// 지난 발생 시각 / 다음 발생 시각. 하루씩 옮겨보며 찾는다 —
/// 달마다 날 수가 다르고 서머타임도 있어서 직접 계산하는 것보다 이 편이 안전하다.
func lastAlarmTime(_ a: Alarm, before now: Date, _ cal: Calendar = .current) -> Date? {
    for back in 0...400 {
        guard let day = cal.date(byAdding: .day, value: -back, to: now),
              let at = alarmOccurrence(a, onDay: day, cal) else { continue }
        if at <= now { return at }
    }
    return nil
}

func nextAlarmTime(_ a: Alarm, after now: Date, _ cal: Calendar = .current) -> Date? {
    for ahead in 0...400 {
        guard let day = cal.date(byAdding: .day, value: ahead, to: now),
              let at = alarmOccurrence(a, onDay: day, cal) else { continue }
        if at > now { return at }
    }
    return nil
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
    /// 알림 줄 → 마지막으로 끈 발생 시각 / 배너를 띄운 발생 시각 (epoch).
    /// 줄 내용을 키로 쓴다 — 줄을 고치면 그 알림은 새 것으로 취급된다.
    var alarmAck: [String: Double] = [:]
    var alarmSeen: [String: Double] = [:]
    /// 다시 알림을 누른 알림 → 다시 울릴 시각 (epoch)
    var alarmSnooze: [String: Double] = [:]
    /// 메뉴에서 조절한 크기·간격. config.sh 는 기본값으로 두고 여기 값이 이긴다.
    /// config.sh 를 프로그램이 덮어쓰면 주석과 형식이 깨지기 때문이다.
    var look: [String: Double] = [:]

    init(config: Config) {
        folded = config.foldedDefault.union(["plane/Backlog"])
        guard let d = try? Data(contentsOf: stateURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if let f = j["folded"] as? [String] { folded = Set(f) }
        if let e = j["memos"] as? [String] { expandedMemos = Set(e) }
        if let o = j["open"] as? Bool { open = o }
        if let a = j["showAll"] as? [String] { showAll = Set(a) }
        if let l = j["look"] as? [String: Double] { look = l }
        if let a = j["alarmAck"] as? [String: Double] { alarmAck = a }
        if let a = j["alarmSeen"] as? [String: Double] { alarmSeen = a }
        if let a = j["alarmSnooze"] as? [String: Double] { alarmSnooze = a }
        if let r = j["frame"] as? [String: Double],
           let x = r["x"], let y = r["y"], let w = r["w"], let h = r["h"] {
            frame = NSRect(x: x, y: y, width: w, height: h)
        }
    }

    func save() {
        var j: [String: Any] = ["folded": Array(folded),
                                "memos": Array(expandedMemos),
                                "showAll": Array(showAll),
                                "look": look,
                                "alarmAck": alarmAck,
                                "alarmSeen": alarmSeen,
                                "alarmSnooze": alarmSnooze,
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
        case ok, fail, run, info, alarm

        var glyph: String {
            switch self {
            case .ok: return "✓"
            case .fail: return "✗"
            case .run: return "◍"
            case .info: return "•"
            case .alarm: return "🔔"
            }
        }
        var color: NSColor {
            switch self {
            case .ok: return rgb("#3FBF8F")
            case .fail: return rgb("#F0705A")
            case .run: return rgb("#E0A54B")
            case .info: return rgb("#8FB8BC")
            case .alarm: return rgb("#DE9AA8")
            }
        }
        /// 알림은 좀 더 오래 둔다. 그래도 계속 떠 있진 않는다 —
        /// 안 끈 표시는 메뉴바와 목록에 남으므로 화면을 가릴 이유가 없다.
        var seconds: Double { self == .alarm ? 20 : 5 }

    }

    private static var stack: [Banner] = []
    private let panel: NSPanel
    private var timer: Timer?
    private let onClick: (() -> Void)?
    private let onAction: (() -> Void)?

    static func show(_ kind: Kind, title: String, subtitle: String, body: String,
                     theme: Theme, sound: String? = nil, action: String? = nil,
                     onAction: (() -> Void)? = nil, onClick: (() -> Void)? = nil) {
        let b = Banner(kind, title: title, subtitle: subtitle, body: body,
                       theme: theme, action: action, onAction: onAction, onClick: onClick)
        stack.append(b)
        b.layout()
        b.appear(kind.seconds)
        play(sound)
    }

    static func audition(_ sound: String?) { play(sound) }

    /// 시스템 소리 이름이면 이름으로, 경로면 파일로 재생한다. 빈 값이면 조용히.
    private static func play(_ sound: String?) {
        guard let sound, !sound.isEmpty else { return }
        if sound.contains("/") || sound.hasSuffix(".aiff") || sound.hasSuffix(".wav")
            || sound.hasSuffix(".mp3") || sound.hasSuffix(".m4a") {
            let path = (sound as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                NSSound(contentsOfFile: path, byReference: true)?.play()
                return
            }
            log("소리 파일 없음: \(path)")
            return
        }
        if let s = NSSound(named: sound) { s.play() } else { log("소리 이름 없음: \(sound)") }
    }

    private init(_ kind: Kind, title: String, subtitle: String, body: String,
                 theme: Theme, action: String? = nil, onAction: (() -> Void)? = nil,
                 onClick: (() -> Void)?) {
        self.onClick = onClick
        self.onAction = onAction
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
        // 버튼이 있으면 본문 폭을 줄여 겹치지 않게 한다
        let bodyWidth = action == nil ? tw : tw - 104
        bod.frame = NSRect(x: x, y: h - 62, width: bodyWidth, height: 16)
        for v in [t, sub, bod] { blur.addSubview(v) }

        if let action {
            let b = NSButton(title: action, target: self, action: #selector(actioned))
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11)
            b.frame = NSRect(x: w - 116, y: 8, width: 102, height: 22)
            blur.addSubview(b)
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        blur.addGestureRecognizer(click)
    }

    @objc private func clicked() {
        onClick?()
        dismiss()
    }

    /// 배너의 버튼(다시 알림). 배너를 여는 클릭과 섞이지 않게 따로 받는다.
    @objc private func actioned() {
        onAction?()
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

    private func appear(_ seconds: Double = 5) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            panel.animator().alphaValue = 1
        }
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
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

/// 글자 배경을 둥근 네모로 그린다. NSAttributedString 의 .backgroundColor 는
/// 각진 네모로만 칠해지므로, 지정한 색만 골라 직접 그린다.
/// roundColor 와 같은 색일 때만 개입하고 나머지(칸 제목 띠·알약)는 원래대로 둔다.
final class HoverLayoutManager: NSLayoutManager {
    var roundColor: NSColor?
    var radius: CGFloat = 5
    var pad: CGFloat = 3          // 좌우로 조금 넓혀야 알약처럼 보인다

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        guard let want = roundColor, color == want else {
            super.fillBackgroundRectArray(rectArray, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }
        color.setFill()
        let path = NSBezierPath()
        for i in 0..<rectCount {
            // 위아래로 살짝 줄여 윗줄·아랫줄과 붙지 않게 한다
            let r = rectArray[i].insetBy(dx: -pad, dy: 0.5)
            path.append(NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius))
        }
        path.fill()
    }
}

/// 알림 하나를 고르는 창. 아이폰 알람과 같은 순서(시각 → 반복 → 이름 → 소리 →
/// 다시 알림)로 놓았다. 굴리는 휠 피커는 macOS 에 없으므로 시각은
/// NSDatePicker(시:분 + 스테퍼)를 쓴다 — 맥 시스템 설정과 같은 컨트롤이다.
final class AlarmSheet: NSObject {
    static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                         "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    let view = NSView(frame: NSRect(x: 0, y: 0, width: 356, height: 200))
    private let time = NSDatePicker()
    private let every = NSSegmentedControl()
    private var days: [NSButton] = []
    private let monthDay = NSPopUpButton()
    private let onceDate = NSDatePicker()
    private let what = NSTextField()
    private let sound = NSPopUpButton()
    private let snooze = NSButton()

    init(_ a: Alarm?) {
        super.init()
        let ko = Strings.lang == "ko"

        func caption(_ text: String, _ y: CGFloat) {
            let f = NSTextField(labelWithString: text)
            f.font = .systemFont(ofSize: 11, weight: .medium)
            f.textColor = .secondaryLabelColor
            f.frame = NSRect(x: 0, y: y, width: 52, height: 16)
            f.alignment = .right
            view.addSubview(f)
        }

        // 시각
        caption(L("alarmTime"), 176)
        time.datePickerStyle = .textFieldAndStepper
        time.datePickerElements = .hourMinute
        time.frame = NSRect(x: 60, y: 172, width: 92, height: 24)
        var comp = DateComponents()
        comp.year = 2026; comp.month = 1; comp.day = 1
        comp.hour = a?.hour ?? 9; comp.minute = a?.minute ?? 0
        time.dateValue = Calendar.current.date(from: comp) ?? Date()
        view.addSubview(time)

        // 반복
        caption(L("alarmRepeat"), 140)
        every.segmentCount = 4
        for (i, t) in [L("everyDay"), L("everyWeek"), L("everyMonth"), L("everyOnce")].enumerated() {
            every.setLabel(t, forSegment: i)
            every.setWidth(66, forSegment: i)
        }
        every.selectedSegment = {
            switch a?.every ?? .day {
            case .day: return 0
            case .week: return 1
            case .month: return 2
            case .year, .once: return 3
            }
        }()
        every.target = self
        every.action = #selector(everyChanged)
        every.frame = NSRect(x: 60, y: 136, width: 268, height: 24)
        view.addSubview(every)

        // 요일 (매주)
        let names = ko ? ["일", "월", "화", "수", "목", "금", "토"]
                       : ["S", "M", "T", "W", "T", "F", "S"]
        for i in 0..<7 {
            let b = NSButton(frame: NSRect(x: 60 + CGFloat(i) * 34, y: 100, width: 30, height: 26))
            b.title = names[i]
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11, weight: .medium)
            b.state = (a?.weekdays.contains(i + 1) ?? false) ? .on : .off
            days.append(b)
            view.addSubview(b)
        }

        // 며칠 (매월)
        monthDay.frame = NSRect(x: 60, y: 100, width: 74, height: 26)
        monthDay.addItems(withTitles: (1...31).map { ko ? "\($0)일" : "\($0)" })
        monthDay.selectItem(at: max(0, (a?.every == .month ? (a?.day ?? 1) : 1) - 1))
        view.addSubview(monthDay)

        // 날짜 (한 번)
        onceDate.datePickerStyle = .textFieldAndStepper
        onceDate.datePickerElements = .yearMonthDay
        onceDate.frame = NSRect(x: 60, y: 100, width: 130, height: 26)
        if let a, a.every == .once || a.every == .year {
            var c = DateComponents()
            c.year = a.every == .once ? a.year : Calendar.current.component(.year, from: Date())
            c.month = a.month; c.day = a.day
            onceDate.dateValue = Calendar.current.date(from: c) ?? Date()
        } else {
            onceDate.dateValue = Date()
        }
        view.addSubview(onceDate)

        // 알릴 내용
        caption(L("alarmWhat"), 68)
        what.frame = NSRect(x: 60, y: 64, width: 268, height: 24)
        what.stringValue = a?.title ?? ""
        what.placeholderString = L("alarmWhat")
        view.addSubview(what)

        // 소리
        caption(L("alarmSound"), 32)
        sound.frame = NSRect(x: 60, y: 28, width: 130, height: 26)
        sound.addItems(withTitles: [L("soundDefault"), L("soundNone")] + AlarmSheet.sounds)
        if let s = a?.sound, !s.isEmpty {
            sound.selectItem(at: s == "none" ? 1 : (AlarmSheet.sounds.firstIndex(of: s).map { $0 + 2 } ?? 0))
        }
        sound.target = self
        sound.action = #selector(playSound)
        view.addSubview(sound)

        let play = NSButton(title: "▶ " + L("soundPlay"), target: self, action: #selector(playSound))
        play.bezelStyle = .rounded
        play.font = .systemFont(ofSize: 11)
        play.frame = NSRect(x: 196, y: 28, width: 96, height: 26)
        view.addSubview(play)

        // 다시 알림
        snooze.setButtonType(.switch)
        snooze.title = L("alarmSnooze")
        snooze.font = .systemFont(ofSize: 11)
        snooze.state = (a?.snooze ?? 0) > 0 ? .on : .off
        snooze.frame = NSRect(x: 60, y: 2, width: 268, height: 20)
        view.addSubview(snooze)

        what.nextKeyView = sound
        everyChanged()
    }

    /// 반복 종류에 따라 아래 한 줄만 바꿔 보여준다.
    @objc func everyChanged() {
        let pick = every.selectedSegment
        days.forEach { $0.isHidden = pick != 1 }
        monthDay.isHidden = pick != 2
        onceDate.isHidden = pick != 3
    }

    @objc func playSound() {
        switch sound.indexOfSelectedItem {
        case 0: Banner.audition("Ping")
        case 1: break
        default: Banner.audition(AlarmSheet.sounds[sound.indexOfSelectedItem - 2])
        }
    }

    var firstField: NSView { what.stringValue.isEmpty ? what : time }

    /// 화면에서 고른 값을 알림 하나로. 요일을 안 고른 매주 알림은 nil.
    func result(keeping old: Alarm?) -> Alarm? {
        let cal = Calendar.current
        var a = old ?? Alarm()
        a.hour = cal.component(.hour, from: time.dateValue)
        a.minute = cal.component(.minute, from: time.dateValue)
        a.title = what.stringValue.trimmingCharacters(in: .whitespaces)
        guard !a.title.isEmpty else { return nil }

        switch every.selectedSegment {
        case 0: a.every = .day
        case 1:
            a.every = .week
            a.weekdays = Set(days.enumerated().filter { $0.element.state == .on }.map { $0.offset + 1 })
            guard !a.weekdays.isEmpty else { return nil }
        case 2:
            a.every = .month
            a.day = monthDay.indexOfSelectedItem + 1
        default:
            a.every = .once
            let c = cal.dateComponents([.year, .month, .day], from: onceDate.dateValue)
            a.year = c.year ?? 2026; a.month = c.month ?? 1; a.day = c.day ?? 1
        }

        switch sound.indexOfSelectedItem {
        case 0: a.sound = ""
        case 1: a.sound = "none"
        default: a.sound = AlarmSheet.sounds[sound.indexOfSelectedItem - 2]
        }
        a.snooze = snooze.state == .on ? 10 : 0
        a.on = old?.on ?? true
        return a
    }

    var weekdayMissing: Bool {
        every.selectedSegment == 1 && days.allSatisfy { $0.state == .off }
    }
}

/// 마우스가 지나간 자리를 알려주는 텍스트 뷰.
/// NSTextView 는 줄 단위 hover 를 주지 않아서 직접 추적한다.
/// NSTextView 가 스스로 만든 추적 영역(링크 커서)은 건드리면 안 되므로
/// 내가 넣은 것만 기억해두고 그것만 지운다.
final class HoverTextView: NSTextView {
    var onHover: ((NSPoint?) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited,
                                         .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        hoverArea = a
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHover?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(nil)
    }
}

final class Widget: NSObject, NSApplicationDelegate, NSTextViewDelegate,
                    NSTextFieldDelegate, NSSearchFieldDelegate,
                    UNUserNotificationCenterDelegate {
    var config = Config.load()
    lazy var theme = Theme.named(config.theme)
    lazy var state = UIState(config: config)

    var statusItem: NSStatusItem!
    var contextMenu: NSMenu!
    var panel: NSPanel!
    var textView: HoverTextView!
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
    /// hover: 줄마다 글자 범위를 적어두고, 마우스가 든 줄에만 배경을 깐다.
    var hoverRanges: [NSRange] = []
    var hoverRange: NSRange?
    var hoverSaved: [(NSRange, NSColor)] = []
    var hoverColorCache: NSColor?
    var alarmPending = 0        // 울렸는데 안 끈 알림 수 (메뉴바 종 표시)
    var alarmTimer: Timer?
    var alarmDeleted = false    // 창의 삭제 버튼을 눌렀는지
    var lookInfoItem: NSMenuItem!
    var lookHoverItem: NSMenuItem!
    var adjusting = false
    var canPostNative = false

    // ── 시작 ──
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Strings.lang = config.lang
        applyLook()      // ui-state.json 에 저장된 크기·간격 반영
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
            self.checkAlarms()      // 자는 동안 지나간 알림을 여기서 잡는다
        }

        // 알림은 조회와 무관하게 30초마다 스스로 확인한다 (네트워크 없음)
        alarmTimer = Timer.scheduledTimer(timeInterval: 30, target: self,
                                          selector: #selector(checkAlarms),
                                          userInfo: nil, repeats: true)
        alarmTimer?.tolerance = 5
        checkAlarms()

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
        menu.addItem(.separator())
        let look = NSMenuItem(title: L("menuLook"), action: nil, keyEquivalent: "")
        look.submenu = buildLookMenu()
        menu.addItem(look)
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

    /// 크기·간격을 메뉴에서 바로 바꾼다. 설정 파일을 열지 않아도 되고,
    /// 누르면 그 자리에서 다시 그려지므로 보면서 맞출 수 있다.
    /// tag 부호가 방향(+/−), 절댓값이 무엇을 바꾸는지다.
    func buildLookMenu() -> NSMenu {
        let m = NSMenu()

        lookInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lookInfoItem.isEnabled = false
        m.addItem(lookInfoItem)
        m.addItem(.separator())

        func pair(_ what: String, _ up: String, _ down: String, _ tag: Int,
                  keys: (String, String) = ("", "")) {
            for (label, key, t) in [(up, keys.0, tag), (down, keys.1, -tag)] {
                let item = NSMenuItem(title: "\(what) \(label)",
                                      action: #selector(adjustLook(_:)), keyEquivalent: key)
                if !key.isEmpty { item.keyEquivalentModifierMask = [.command] }
                item.tag = t
                item.target = self
                m.addItem(item)
            }
        }

        pair(L("lookText"), L("lookBigger"), L("lookSmaller"), 1, keys: ("+", "-"))
        m.addItem(.separator())
        pair(L("lookLine"), L("lookWider"), L("lookNarrower"), 2)
        pair(L("lookRow"), L("lookWider"), L("lookNarrower"), 3)
        m.addItem(.separator())
        pair(L("lookHead"), L("lookBigger"), L("lookSmaller"), 4)
        pair(L("lookWidth"), L("lookWider"), L("lookNarrower"), 5)
        m.addItem(.separator())

        lookHoverItem = NSMenuItem(title: L("lookHover"), action: #selector(toggleHover),
                                   keyEquivalent: "")
        lookHoverItem.target = self
        m.addItem(lookHoverItem)
        for (label, t) in [(L("lookHoverUp"), 6), (L("lookHoverDown"), -6)] {
            let item = NSMenuItem(title: label, action: #selector(adjustLook(_:)), keyEquivalent: "")
            item.tag = t
            item.target = self
            m.addItem(item)
        }
        m.addItem(.separator())

        for (title, sel) in [(L("lookReset"), #selector(resetLook)),
                             (L("menuOpenAlarm"), #selector(openAlarm)),
                             (L("menuOpenConfig"), #selector(openConfig))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            m.addItem(item)
        }
        return m
    }

    @objc func adjustLook(_ sender: NSMenuItem) {
        let dir: Double = sender.tag > 0 ? 1 : -1
        switch abs(sender.tag) {
        case 1: setLook("fontScale", config.fontScale + 0.05 * dir, 0.8, 1.6)
        case 2: setLook("lineSpacing", config.lineSpacing + dir, 0, 14)
        case 3: setLook("rowGap", config.rowGap + dir, 0, 14)
        case 4: setLook("headSize", config.headSize + 0.5 * dir, 9, 20)
        case 5: setLook("width", config.width + 10 * dir, 260, 560)
        case 6: setLook("hoverStrength", config.hoverStrength + 10 * dir, 0, 100)
        default: return
        }
    }

    @objc func toggleHover() {
        setLook("hover", config.hover ? 0 : 1, 0, 1)
    }

    /// 값 하나를 바꾸고 저장한 뒤 그 자리에서 다시 그린다.
    func setLook(_ key: String, _ raw: Double, _ lo: Double, _ hi: Double) {
        let v = (min(max(raw, lo), hi) * 100).rounded() / 100
        state.look[key] = v
        state.save()
        applyLook()
        render()
        if panel != nil && panel.isVisible { fitAndAnchor() }
        updateLookMenu()
    }

    @objc func resetLook() {
        state.look = [:]
        state.save()
        applyLook()
        render()
        if panel != nil && panel.isVisible { fitAndAnchor() }
        updateLookMenu()
    }

    /// ui-state.json 의 값이 config.sh 값을 덮어쓴다. 없으면 config.sh 그대로.
    func applyLook() {
        let base = Config.load()            // config.sh 를 다시 읽어 기준값으로 삼는다
        config.fontScale = state.look["fontScale"] ?? base.fontScale
        config.lineSpacing = state.look["lineSpacing"] ?? base.lineSpacing
        config.rowGap = state.look["rowGap"] ?? base.rowGap
        config.headSize = state.look["headSize"] ?? base.headSize
        config.width = state.look["width"] ?? base.width
        config.hoverStrength = state.look["hoverStrength"] ?? base.hoverStrength
        config.hover = state.look["hover"].map { $0 > 0 } ?? base.hover

        Metrics.fontScale = CGFloat(config.fontScale)
        Metrics.lineSpacing = CGFloat(config.lineSpacing)
        Metrics.rowGap = CGFloat(config.rowGap)
        Metrics.headSize = CGFloat(config.headSize)
        hoverColorCache = nil               // 세기가 바뀌면 색을 다시 만든다
        setHover(nil)
    }

    /// 하위 메뉴 맨 위에 지금 값을 적어둔다 — 몇 번 눌렀는지 세지 않아도 되게.
    func updateLookMenu() {
        guard lookInfoItem != nil else { return }
        let pct = Int((config.fontScale * 100).rounded())
        let num = { (d: Double) in
            d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
        }
        lookInfoItem.title = "\(L("lookNow"))  "
            + "\(L("lookText")) \(pct)%  ·  \(L("lookLine")) \(num(config.lineSpacing))  ·  "
            + "\(L("lookRow")) \(num(config.rowGap))  ·  \(L("lookHead")) \(num(config.headSize))"
            + "  ·  \(L("lookWidth")) \(num(config.width))"
        lookHoverItem.state = config.hover ? .on : .off
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
        let size = NSSize(width: CGFloat(config.width), height: 460)
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
        panel.acceptsMouseMovedEvents = true        // 없으면 hover 가 안 온다

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
        refreshButton.font = .monospacedSystemFont(ofSize: fs(13), weight: .medium)
        refreshButton.toolTip = L("tipRefresh")

        searchField = NSSearchField()
        searchField.placeholderString = L("search")
        searchField.font = .systemFont(ofSize: fs(11.5))
        searchField.delegate = self
        searchField.focusRingType = .none

        textView = HoverTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        textView.onHover = { [weak self] point in self?.hover(at: point) }
        // TextKit 1 로 내려앉힌 뒤 배경을 둥글게 그리는 매니저로 바꾼다.
        // 순서를 바꾸면(컨테이너 설정 뒤에 교체) 폭 추적이 풀려 줄이 어긋난다.
        _ = textView.layoutManager
        textView.textContainer?.replaceLayoutManager(HoverLayoutManager())
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
        f.font = mono ? .monospacedSystemFont(ofSize: fs(size), weight: weight)
                      : .systemFont(ofSize: fs(size), weight: weight)
        f.textColor = color
        return f
    }

    /// 메뉴바 아이콘 바로 아래, 아이콘 가운데에 맞춰 붙인다.
    /// 화면 밖으로 나가지 않게 좌우로 밀어 넣는다.
    func anchorFrame(height: CGFloat) -> NSRect {
        let w = CGFloat(config.width)
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

    /// 로그인 직후에는 메뉴바 아이콘이 아직 자리를 못 잡아서 창이 엉뚱한 곳에 붙는다.
    /// 아이콘 자리가 생길 때까지 몇 번 더 붙여본다.
    func reanchorSoon(_ delays: [Double] = [0.4, 1.2, 2.5, 4.0]) {
        guard (statusItem?.button?.window?.frame.height ?? 0) < 1 else { return }
        for d in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self, self.panel?.isVisible == true,
                      (self.statusItem?.button?.window?.frame.height ?? 0) >= 1 else { return }
                self.fitAndAnchor()
            }
        }
    }

    /// 내용 높이에 맞춰 창을 줄이고 아이콘 아래로 붙인다.
    /// 창 폭이 바뀌면 오른쪽 정렬(개수)과 띠 배경이 어긋나므로 한 번 더 그린다.
    func fitAndAnchor() {
        guard !adjusting else { return }
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        adjusting = true
        lm.ensureLayout(for: tc)
        let textHeight = lm.usedRect(for: tc).height
        let chrome: CGFloat = fs(32) + fs(30) + 26      // 헤더 + 검색칸 + 여백
        panel.setFrame(anchorFrame(height: ceil(textHeight) + chrome), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        // 데모용 인스턴스에서만 — 문서 스크린샷 좌표
        if ProcessInfo.processInfo.environment["MW_DIR"] != nil {
            log("창 \(panel.windowNumber) \(panel.frame)"
                + "  아이콘 \(statusItem.button?.window?.frame ?? .zero)"
                + "  화면 \(NSScreen.screens.map { $0.frame })")
        }
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
        // 알림 칸도 파일에서 직접. 울린 것이 위, 그 아래로 예정 시각 순.
        // 한 번만 울리는 알림은 끄고 나면 다음 시각이 없어 목록에서 사라진다.
        let now = Date()
        let alarms = loadAlarms()
        primeAlarms(alarms, now: now)
        var alarmRows: [(Row, Double)] = []
        var pending = 0
        for a in alarms {
            var r = Row()
            r.kind = "alarm"; r.index = a.src; r.title = a.title; r.on = a.on
            if let at = alarmPendingAt(a, now: now) {
                r.pending = true
                r.id = alarmStamp(at, now: now)
                pending += 1
                alarmRows.append((r, at.timeIntervalSince1970))
            } else if let at = nextAlarmTime(a, after: now) {
                r.id = alarmStamp(at, now: now)
                alarmRows.append((r, at.timeIntervalSince1970))
            } else if !a.on {
                alarmRows.append((r, .greatestFiniteMagnitude))   // 꺼둔 한 번짜리도 남긴다
            }
        }
        // 울린 것 → 켜둔 것(시각 순) → 꺼둔 것
        alarmRows.sort {
            if $0.0.pending != $1.0.pending { return $0.0.pending }
            if $0.0.on != $1.0.on { return $0.0.on }
            return $0.1 < $1.1
        }
        alarmPending = pending
        let alarmSection = Section(key: "alarm", title: config.alarmTitle,
                                   hue: "rose", groups: [Group(rows: alarmRows.map { $0.0 })])
        // Order comes from MW_SECTION_ORDER. "notes" means the local notes section;
        // any section the config does not mention is kept, at the end.
        var pool = built
        pool.append(memoSection)
        pool.append(alarmSection)
        var ordered: [Section] = []
        for wanted in config.sectionOrder {
            var key = (wanted == "notes" || wanted == "memo") ? "memo" : wanted
            if key == "alarms" { key = "alarm" }
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
                    if r.kind == "alarm" {
                        out.append("     \(r.pending ? "🔔" : "○") \(r.id)  \(r.title)"
                                   + (r.on ? "  ●" : "  ○"))
                    } else if r.kind == "memo" {
                        let ex = state.expandedMemos.contains(r.title)
                        out.append("     ☐ \(ex ? "▾" : "▸") \(r.title)")
                        if ex && !r.detail.isEmpty { out.append("         \(r.detail)") }
                    } else {
                        var tail = ""
                        if !r.badge.isEmpty { tail = "  💬\(r.badge)" }
                        if !r.ci.isEmpty { tail += r.ci == "success" ? " ✓" : (r.ci == "failed" ? " ✗" : " ◐") }
                        else if r.ok && r.badge.isEmpty { tail += " ✓" }
                        let t = r.title.count > 32 ? String(r.title.prefix(32)) + "…" : r.title
                        out.append("     \(idLabel(r, sec: sec))  \(t)\(tail)")
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
        // 다시 그리면 이전 hover 범위는 의미가 없다
        hoverRanges = []
        hoverRange = nil
        hoverSaved = []

        /// hover 대상 줄을 붙이면서 그 글자 범위를 적어둔다.
        /// 끝의 줄바꿈은 빼야 배경이 줄 끝에 혼자 튀지 않는다.
        func appendHoverable(_ piece: NSAttributedString) {
            let start = out.length
            out.append(piece)
            let end = out.length
            let drop = piece.string.hasSuffix("\n") ? 1 : 0
            if end - drop > start { hoverRanges.append(NSRange(location: start,
                                                              length: end - drop - start)) }
        }

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
                    appendHoverable(groupLine(g, count: rows.count, total: g.rows.count,
                                              folded: gfolded, key: gkey, hue: sec.hue,
                                              width: width))
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
                for r in shown {
                    appendHoverable(rowLine(r, sec: sec, width: width, idColor: gc))
                }
                if capped {
                    appendHoverable(moreLine(rows.count - cap, key: key,
                                             color: gc ?? theme.mute, width: width))
                } else if cap > 0 && query.isEmpty && state.showAll.contains(key)
                            && rows.count > cap {
                    appendHoverable(lessLine(key: key, color: gc ?? theme.mute, width: width))
                }
            }
            // 메모·알림 칸 끝에 추가 버튼
            if sec.key == "memo" && query.isEmpty {
                appendHoverable(addMemoLine(width: width))
            }
            if sec.key == "alarm" && query.isEmpty {
                appendHoverable(addAlarmLine(width: width))
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

    // ── 알림 ──

    /// 방금 적은 알림이 "오늘 아침에 이미 지났다"고 울리는 것을 막는다.
    /// 처음 본 줄은 지난 회차를 이미 끈 것으로 두고, 다음 회차부터 울린다.
    /// 지운 알림의 상태도 여기서 버려 ui-state.json 이 계속 불어나지 않게 한다.
    func primeAlarms(_ alarms: [Alarm], now: Date) {
        var changed = false
        let live = Set(alarms.map { $0.line })
        for key in state.alarmAck.keys where !live.contains(key) {
            state.alarmAck[key] = nil; changed = true
        }
        for key in state.alarmSeen.keys where !live.contains(key) {
            state.alarmSeen[key] = nil; changed = true
        }
        for key in state.alarmSnooze.keys where !live.contains(key) {
            state.alarmSnooze[key] = nil; changed = true
        }
        for a in alarms where state.alarmAck[a.line] == nil && state.alarmSeen[a.line] == nil {
            let at = lastAlarmTime(a, before: now)?.timeIntervalSince1970 ?? 0
            state.alarmAck[a.line] = at
            state.alarmSeen[a.line] = at
            changed = true
            log("알림 새로 봄 — \(a.title)")
        }
        if changed { state.save() }
    }

    /// 울렸는데 아직 안 끈 알림이면 그 발생 시각. 아니면 nil.
    /// 지난 것은 MW_ALARM_GRACE_HOURS(기본 12시간) 안의 것만 본다 — 자거나
    /// 꺼져 있던 사이의 알림이 며칠치 쏟아지지 않게 한다.
    func alarmPendingAt(_ a: Alarm, now: Date) -> Date? {
        guard a.on else { return nil }
        // 다시 알림을 누른 알림은 그 시각까지 조용하고, 되면 다시 켜진다
        if let again = state.alarmSnooze[a.line] {
            return now.timeIntervalSince1970 >= again ? Date(timeIntervalSince1970: again) : nil
        }
        guard let at = lastAlarmTime(a, before: now) else { return nil }
        guard now.timeIntervalSince(at) <= config.alarmGrace * 3600 else { return nil }
        if let acked = state.alarmAck[a.line], acked + 1 >= at.timeIntervalSince1970 { return nil }
        return at
    }

    /// 30초마다. 새로 울릴 것이 있으면 배너를 띄우고, 안 끈 개수가 바뀌면 다시 그린다.
    @objc func checkAlarms() {
        let now = Date()
        let alarms = loadAlarms()
        primeAlarms(alarms, now: now)
        var rang: [(Alarm, Date)] = []
        var pending = 0
        for a in alarms {
            guard let at = alarmPendingAt(a, now: now) else { continue }
            pending += 1
            if (state.alarmSeen[a.line] ?? 0) + 1 < at.timeIntervalSince1970 {
                state.alarmSeen[a.line] = at.timeIntervalSince1970
                rang.append((a, at))
            }
        }
        if !rang.isEmpty { state.save() }
        for (a, at) in rang {
            log("알림 울림 — \(a.title) (\(at))")
            let sound = a.sound == "none" ? "" : (a.sound.isEmpty ? config.soundAlarm : a.sound)
            let line = a.line
            Banner.show(.alarm, title: L("alarmRang"), subtitle: alarmStamp(at, now: now),
                        body: a.title, theme: theme, sound: sound,
                        action: a.snooze > 0 ? L("snoozeNow") : nil,
                        onAction: a.snooze > 0 ? { [weak self] in self?.snoozeAlarm(line, a.snooze) } : nil)
        }
        if pending != alarmPending || !rang.isEmpty {
            alarmPending = pending
            reload()
        }
    }

    /// 다시 알림 — 지금 회차를 끄고 N분 뒤에 다시 울리게 한다.
    func snoozeAlarm(_ line: String, _ minutes: Int) {
        let again = Date().addingTimeInterval(Double(minutes) * 60)
        state.alarmSnooze[line] = again.timeIntervalSince1970
        state.alarmSeen[line] = 0
        state.save()
        log("다시 알림 \(minutes)분 — \(line)")
        checkAlarms()
        reload()
    }

    /// 목록에 보여줄 시각 문구. 오늘이면 시간만, 가까우면 요일, 멀면 날짜.
    func alarmStamp(_ at: Date, now: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: Strings.lang == "ko" ? "ko_KR" : "en_US")
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: at)).day ?? 0
        f.dateFormat = "HH:mm"
        let hm = f.string(from: at)
        switch days {
        case 0: return hm
        case 1: return "\(L("alarmTomorrow")) \(hm)"
        case -1: return "\(L("alarmYesterday")) \(hm)"
        case 2...6:
            f.dateFormat = "E"
            return "\(f.string(from: at)) \(hm)"
        default:
            f.dateFormat = "M/d"
            return "\(f.string(from: at)) \(hm)"
        }
    }

    // ── hover ──

    /// 마우스가 어느 줄에 들어갔는지 찾아 그 줄에만 배경을 깐다.
    /// point 가 nil 이면(창 밖으로 나감) 지운다.
    func hover(at point: NSPoint?) {
        guard config.hover else { return }
        guard let point, let idx = charIndex(at: point) else { return setHover(nil) }
        setHover(hoverRanges.first { NSLocationInRange(idx, $0) })
    }

    /// 화면 좌표 → 글자 위치. 줄 아래 빈 자리에서 마지막 줄이 켜지지 않게
    /// 그 줄의 높이 안에 있는지도 확인한다.
    func charIndex(at point: NSPoint) -> Int? {
        guard let lm = textView.layoutManager, let tc = textView.textContainer,
              textView.textStorage?.length ?? 0 > 0 else { return nil }
        let inset = textView.textContainerInset
        let p = NSPoint(x: point.x - inset.width, y: point.y - inset.height)
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: nil)
        let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard p.y >= line.minY - 1, p.y <= line.maxY + 1 else { return nil }
        return lm.characterIndexForGlyph(at: glyph)
    }

    /// hover 배경색. 테마의 선 색을 글자색 쪽으로 밀어 밝게 만든다.
    /// 세기는 MW_HOVER_STRENGTH (0~100).
    var hoverColor: NSColor {
        if let c = hoverColorCache { return c }
        let k = CGFloat(min(max(config.hoverStrength, 0), 100)) / 100
        // 글자색 쪽으로 조금만 민다 — 많이 밀면 흰 띠처럼 보인다
        let base = theme.line.blended(withFraction: 0.16 * k, of: theme.ink) ?? theme.line
        let c = base.withAlphaComponent(0.55 + 0.45 * k)
        hoverColorCache = c        // 같은 인스턴스여야 레이아웃 매니저가 알아본다
        return c
    }

    func setHover(_ range: NSRange?) {
        guard hoverRange != range else { return }
        if let old = hoverRange { clearHover(old) }
        hoverRange = range
        if let range { paintHover(range) }
    }

    /// 코멘트 수 알약처럼 이미 배경이 있는 조각은 원래 색을 적어두고
    /// hover 가 풀릴 때 되돌린다. 안 그러면 알약 배경이 사라진다.
    func paintHover(_ range: NSRange) {
        guard let ts = textView.textStorage, NSMaxRange(range) <= ts.length else { return }
        hoverSaved = []
        ts.enumerateAttribute(.backgroundColor, in: range) { value, sub, _ in
            if let c = value as? NSColor { hoverSaved.append((sub, c)) }
        }
        let c = hoverColor
        if let lm = textView.layoutManager as? HoverLayoutManager {
            lm.roundColor = c
            lm.radius = fs(5)
        }
        ts.addAttribute(.backgroundColor, value: c, range: range)
    }

    func clearHover(_ range: NSRange) {
        guard let ts = textView.textStorage, NSMaxRange(range) <= ts.length else { return }
        ts.removeAttribute(.backgroundColor, range: range)
        for (r, c) in hoverSaved where NSMaxRange(r) <= ts.length {
            ts.addAttribute(.backgroundColor, value: c, range: r)
        }
        hoverSaved = []
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
        p.lineSpacing = Metrics.lineSpacing
        p.paragraphSpacing = Metrics.rowGap
        p.lineBreakMode = .byTruncatingTail
        p.tighteningFactorForTruncation = 0
        return p
    }

    func bandLine(_ sec: Section, count: Int, total: Int,
                  folded: Bool, width: CGFloat) -> NSAttributedString {
        let (bg, rail) = theme.hues[sec.hue] ?? (theme.head, theme.mute)
        let s = NSMutableAttributedString()
        let p = para(width: width, indent: 0)
        p.paragraphSpacingBefore = fs(7)

        // 칸 제목과 그 옆 개수는 MW_FONT_SCALE 을 받지 않는다 — 본문만 키운다.
        s.append(NSAttributedString(string: "▎", attributes: [
            .foregroundColor: rail, .backgroundColor: bg,
            .font: NSFont.systemFont(ofSize: Metrics.headRailSize), .paragraphStyle: p,
        ]))
        let arrow = folded ? "▸" : "▾"
        s.append(NSAttributedString(string: " \(arrow)  \(sec.title)", attributes: [
            .foregroundColor: theme.ink, .backgroundColor: bg,
            .font: NSFont.systemFont(ofSize: Metrics.headSize, weight: .semibold),
            .kern: 0.2,
            .paragraphStyle: p, .link: "tally://fold/\(sec.key)",
        ]))
        let countText = (!query.isEmpty && count != total) ? "\(count)/\(total)" : "\(total)"
        s.append(NSAttributedString(string: "\t\(countText)  ", attributes: [
            .foregroundColor: rail, .backgroundColor: bg,
            .font: NSFont.monospacedDigitSystemFont(ofSize: Metrics.headCountSize, weight: .medium),
            .paragraphStyle: p,
        ]))
        s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
        return s
    }

    func groupLine(_ g: Group, count: Int, total: Int, folded: Bool,
                   key: String, hue: String, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: Indent.group)
        p.paragraphSpacingBefore = fs(2)
        let color = groupColor(g.color)
        let arrow = folded ? "▸" : "▾"
        let countText = (!query.isEmpty && count != total) ? "\(count) / \(total)" : "\(total)"
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "●", attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: fs(7)),
            .paragraphStyle: p, .link: "tally://fold/\(key)",
        ]))
        s.append(NSAttributedString(string: " \(arrow) \(g.title)", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fs(10.5), weight: .semibold),
            .paragraphStyle: p, .link: "tally://fold/\(key)",
        ]))
        s.append(NSAttributedString(string: "\t\(countText)\n", attributes: [
            .foregroundColor: color.withAlphaComponent(0.75),
            .font: NSFont.monospacedDigitSystemFont(ofSize: fs(10), weight: .regular),
            .paragraphStyle: p,
        ]))
        return s
    }

    /// MR 줄 맨 앞에 쓸 말. 번호(!199)보다 브랜치가 눈에 익어서 기본은 브랜치다.
    /// refactor/ · feature/ 같은 접두어는 떼고 마지막 조각만 쓴다.
    /// 번호와 브랜치 전체는 툴팁에 남는다. MW_MR_LABEL="number" 로 되돌릴 수 있다.
    func idLabel(_ r: Row, sec: Section) -> String {
        guard sec.key == "code", config.mrLabel == "branch", !r.ref.isEmpty else { return r.id }
        let last = r.ref.split(separator: "/").last.map(String.init) ?? ""
        return last.isEmpty ? r.id : last
    }

    func rowLine(_ r: Row, sec: Section, width: CGFloat,
                 idColor: NSColor? = nil) -> NSAttributedString {
        let p = para(width: width, indent: Indent.row)
        let s = NSMutableAttributedString()
        let (_, hueRail) = theme.hues[sec.hue] ?? (theme.head, theme.mute)
        let rail = idColor ?? hueRail

        if r.kind == "alarm" {
            // 종을 누르면 이번 회차를 끈다. 시각·제목을 누르면 고친다.
            // 오른쪽 스위치는 알림 자체를 켜고 끈다 (아이폰 목록과 같다).
            let dim = !r.on
            let mark = r.pending ? "🔔" : "○"
            s.append(NSAttributedString(string: mark, attributes: [
                .foregroundColor: r.pending ? theme.badge : theme.mute,
                .font: NSFont.systemFont(ofSize: fs(11)),
                .paragraphStyle: p, .link: "tally://alarm-off/\(r.index)",
                .toolTip: L("tipAlarmOff"),
            ]))
            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: dim ? theme.mute.withAlphaComponent(0.6)
                                      : (r.pending ? theme.badge : rail),
                .font: NSFont.monospacedSystemFont(ofSize: fs(10.5),
                                                   weight: r.pending ? .semibold : .medium),
                .paragraphStyle: p, .link: "tally://alarm-edit/\(r.index)",
                .toolTip: L("tipAlarmEdit"),
            ]
            s.append(NSAttributedString(string: " " + r.id, attributes: attrs))
            attrs[.foregroundColor] = dim ? theme.mute.withAlphaComponent(0.6)
                                          : (r.pending ? theme.ink : theme.mute)
            attrs[.font] = NSFont.systemFont(ofSize: fs(11.5),
                                             weight: r.pending ? .medium : .regular)
            let used = s.size().width
            s.append(NSAttributedString(
                string: " " + fit(r.title, attrs, into: width - Indent.row - used - fs(24)),
                attributes: attrs))
            s.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: p]))
            s.append(NSAttributedString(string: r.on ? "●" : "○", attributes: [
                .foregroundColor: r.on ? theme.accent : theme.mute.withAlphaComponent(0.55),
                .font: NSFont.systemFont(ofSize: fs(10)),
                .paragraphStyle: p, .link: "tally://alarm-toggle/\(r.index)",
                .toolTip: L("tipAlarmOn"),
            ]))
            s.append(NSAttributedString(string: " \n", attributes: [.paragraphStyle: p]))
            return s
        }

        if r.kind == "memo" {
            let expanded = state.expandedMemos.contains(r.title)
            let tip = r.detail.isEmpty ? r.title : r.title + " — " + r.detail
            s.append(NSAttributedString(string: "○", attributes: [
                .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: fs(11)),
                .paragraphStyle: p, .link: "tally://memo-done/\(r.index)",
                .toolTip: L("tipDone"),
            ]))
            s.append(NSAttributedString(string: " ", attributes: [.paragraphStyle: p]))
            let memoAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.ink, .font: NSFont.systemFont(ofSize: fs(11.5)),
                .paragraphStyle: p, .link: "tally://memo-toggle/\(r.index)",
                .toolTip: tip,
            ]
            s.append(NSAttributedString(
                string: (expanded ? "▾ " : "▸ ") + fit(r.title, memoAttrs, into: width - Indent.row - fs(34)),
                attributes: memoAttrs))
            if expanded {
                s.append(NSAttributedString(string: "  ✎", attributes: [
                    .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: fs(10)),
                    .paragraphStyle: p, .link: "tally://memo-edit/\(r.index)",
                    .toolTip: L("tipEdit"),
                ]))
            }
            s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
            if expanded && r.detail.isEmpty {
                let dp = para(width: width, indent: Indent.detail)
                s.append(NSAttributedString(string: L("writeDetail") + "\n", attributes: [
                    .foregroundColor: theme.mute,
                    .font: NSFont.systemFont(ofSize: fs(10.5)),
                    .paragraphStyle: dp, .link: "tally://memo-edit/\(r.index)",
                ]))
            }
            if expanded && !r.detail.isEmpty {
                let dp = para(width: width, indent: Indent.detail)
                dp.lineBreakMode = .byWordWrapping
                s.append(NSAttributedString(string: r.detail + "\n", attributes: [
                    .foregroundColor: theme.mute, .font: NSFont.systemFont(ofSize: fs(10.5)),
                    .paragraphStyle: dp,
                ]))
            }
            return s
        }

        let link = r.url.isEmpty ? nil : r.url
        // 마우스를 올리면 잘린 제목 전체가 보이도록
        let tip = [r.repoFull.isEmpty ? r.repo : r.repoFull, r.id,
                   sec.key == "code" ? r.ref : "", r.title]
            .filter { !$0.isEmpty }.joined(separator: "  ")

        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: rail,
            .font: NSFont.monospacedSystemFont(ofSize: fs(10.5), weight: .medium),
            .paragraphStyle: p, .toolTip: tip,
        ]
        if let link { attrs[.link] = link }
        s.append(NSAttributedString(string: fit(idLabel(r, sec: sec), attrs,
                                                into: width * 0.42),
                                    attributes: attrs))

        if !r.repo.isEmpty {
            var repoAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.mute,
                .font: NSFont.monospacedSystemFont(ofSize: fs(9.5), weight: .regular),
                .paragraphStyle: p, .toolTip: tip,
            ]
            if let link { repoAttrs[.link] = link }
            s.append(NSAttributedString(string: " " + r.repo, attributes: repoAttrs))
        }

        var titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.ink, .font: NSFont.systemFont(ofSize: fs(11.5)),
            .paragraphStyle: p, .toolTip: tip,
        ]
        if let link { titleAttrs[.link] = link }
        // 오른쪽 표시(개수·CI)가 살아남도록 제목을 먼저 줄인다
        let used = s.size().width
        let tailRoom: CGFloat = r.badge.isEmpty
            ? fs(22) : fs(24) + CGFloat(r.badge.count) * fs(7)
        let room = width - Indent.row - used - tailRoom - fs(3)
        s.append(NSAttributedString(string: " " + fit(r.title, titleAttrs, into: room),
                                    attributes: titleAttrs))

        // 오른쪽 표시: 코멘트 수 → CI → 리뷰 해결
        if !r.badge.isEmpty {
            // 안 읽은 코멘트 수 — 배경을 깔아 알약처럼
            s.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: p]))
            s.append(NSAttributedString(string: " \(r.badge) ", attributes: [
                .foregroundColor: theme.badge, .backgroundColor: theme.badgeBg,
                .font: NSFont.monospacedDigitSystemFont(ofSize: fs(10.5), weight: .semibold),
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
                    .font: NSFont.systemFont(ofSize: fs(11), weight: .semibold),
                    .paragraphStyle: p,
                ]))
            }
        }
        // CI 뱃지가 코멘트 수에 밀린 MR 은 상태도 함께
        if !r.badge.isEmpty && !r.ci.isEmpty {
            let mark = r.ci == "success" ? " ✓" : (r.ci == "failed" ? " ✗" : " ◍")
            s.append(NSAttributedString(string: mark, attributes: [
                .foregroundColor: r.ci == "failed" ? theme.danger : theme.accent,
                .font: NSFont.systemFont(ofSize: fs(10)), .paragraphStyle: p,
            ]))
        }
        s.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
        return s
    }

    /// "+ 메모 추가" — 누르면 제목·상세를 함께 적는 창이 뜬다.
    func addMemoLine(width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: Indent.row)
        p.paragraphSpacingBefore = fs(2)
        return NSAttributedString(string: L("addMemo") + "\n", attributes: [
            .foregroundColor: theme.badge.withAlphaComponent(0.9),
            .font: NSFont.systemFont(ofSize: fs(11), weight: .medium),
            .paragraphStyle: p, .link: "tally://memo-add",
            .toolTip: L("tipAddMemo"),
        ])
    }

    /// "+ 알림 추가" — 일정과 내용을 함께 적는 창이 뜬다.
    func addAlarmLine(width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: Indent.row)
        p.paragraphSpacingBefore = fs(2)
        let (_, rail) = theme.hues["rose"] ?? (theme.head, theme.mute)
        return NSAttributedString(string: L("addAlarm") + "\n", attributes: [
            .foregroundColor: rail.withAlphaComponent(0.9),
            .font: NSFont.systemFont(ofSize: fs(11), weight: .medium),
            .paragraphStyle: p, .link: "tally://alarm-add",
            .toolTip: L("tipAlarmAdd"),
        ])
    }

    /// "+7 더" — 누르면 그 묶음만 전부 펼친다.
    func moreLine(_ n: Int, key: String, color: NSColor, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: Indent.row)
        return NSAttributedString(string: L("more", n) + "\n", attributes: [
            .foregroundColor: color.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: fs(10.5), weight: .medium),
            .paragraphStyle: p, .link: "tally://more/\(key)",
            .toolTip: L("tipShowAll"),
        ])
    }

    func lessLine(key: String, color: NSColor, width: CGFloat) -> NSAttributedString {
        let p = para(width: width, indent: Indent.row)
        return NSAttributedString(string: L("less") + "\n", attributes: [
            .foregroundColor: theme.mute,
            .font: NSFont.systemFont(ofSize: fs(10.5), weight: .regular),
            .paragraphStyle: p, .link: "tally://less/\(key)",
        ])
    }

    func plain(_ s: String, color: NSColor, size: CGFloat, italic: Bool = false) -> NSAttributedString {
        var font = NSFont.systemFont(ofSize: fs(size))
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
        if s == "tally://alarm-add" {
            addAlarm()
            return true
        }
        if s.hasPrefix("tally://alarm-off/") {
            turnAlarmOff(Int(s.dropFirst("tally://alarm-off/".count)) ?? -1)
            return true
        }
        if s.hasPrefix("tally://alarm-toggle/") {
            toggleAlarm(Int(s.dropFirst("tally://alarm-toggle/".count)) ?? -1)
            return true
        }
        if s.hasPrefix("tally://alarm-edit/") {
            editAlarm(Int(s.dropFirst("tally://alarm-edit/".count)) ?? -1)
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

    @objc func openAlarm() {
        if !FileManager.default.fileExists(atPath: alarmURL.path) {
            saveAlarmLines(["# \(L("alarmHelp"))"])
        }
        NSWorkspace.shared.open(alarmURL)
    }

    /// 알림 하나를 끈다. 반복 알림은 지우지 않고 이번 회차만 끈다 —
    /// 다음 예정 시각이 되면 다시 울린다.
    func turnAlarmOff(_ src: Int) {
        guard let a = loadAlarms().first(where: { $0.src == src }) else { return }
        let now = Date()
        let at = alarmPendingAt(a, now: now) ?? lastAlarmTime(a, before: now) ?? now
        state.alarmAck[a.line] = at.timeIntervalSince1970
        state.alarmSeen[a.line] = at.timeIntervalSince1970
        state.alarmSnooze[a.line] = nil
        state.save()
        log("알림 끔 — \(a.title)")
        checkAlarms()
        reload()
    }

    /// 알림을 새로 만든다.
    @objc func addAlarm() {
        guard let a = askAlarm(L("addAlarmTitle"), nil) else { return }
        var lines = loadAlarmLines()
        lines.append(alarmLine(a))
        saveAlarmLines(lines)
        checkAlarms()
        reload()
    }

    /// 있는 알림을 고친다. 창의 삭제 버튼을 누르면 그 줄을 지운다.
    func editAlarm(_ src: Int) {
        var lines = loadAlarmLines()
        guard lines.indices.contains(src), let old = parseAlarm(lines[src], src: src) else { return }
        let answer = askAlarm(L("editAlarmTitle"), old)
        if answer == nil && !alarmDeleted { return }
        if alarmDeleted {
            alarmDeleted = false
            lines.remove(at: src)
            forgetAlarm(old.line)
        } else if let a = answer {
            lines[src] = alarmLine(a)
            if a.line != old.line { forgetAlarm(old.line) }   // 줄이 바뀌면 이전 상태는 버린다
        }
        saveAlarmLines(lines)
        checkAlarms()
        reload()
    }

    /// 알림을 켜고 끈다 (아이폰 목록의 스위치). 지우지 않고 잠시 쉬게 하는 것.
    func toggleAlarm(_ src: Int) {
        var lines = loadAlarmLines()
        guard lines.indices.contains(src), var a = parseAlarm(lines[src], src: src) else { return }
        forgetAlarm(a.line)
        a.on = !a.on
        lines[src] = alarmLine(a)
        saveAlarmLines(lines)
        log("알림 \(a.on ? "켬" : "끔") — \(a.title)")
        checkAlarms()
        reload()
    }

    func forgetAlarm(_ line: String) {
        state.alarmAck[line] = nil
        state.alarmSeen[line] = nil
        state.alarmSnooze[line] = nil
        state.save()
    }

    /// 아이폰 알람과 같은 창. 저장을 누르면 알림, 취소면 nil,
    /// 삭제면 nil + alarmDeleted = true.
    func askAlarm(_ title: String, _ old: Alarm?) -> Alarm? {
        let sheet = AlarmSheet(old)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = ""
        alert.addButton(withTitle: old == nil ? L("add") : L("save"))
        alert.addButton(withTitle: L("cancel"))
        if old != nil { alert.addButton(withTitle: L("delete")) }
        alert.accessoryView = sheet.view
        alert.window.initialFirstResponder = sheet.firstField

        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        if old != nil, answer == .alertThirdButtonReturn {
            alarmDeleted = true
            return nil
        }
        guard answer == .alertFirstButtonReturn else { return nil }
        guard let a = sheet.result(keeping: old) else {
            let bad = NSAlert()
            bad.messageText = sheet.weekdayMissing ? L("needWeekday") : L("alarmBad")
            bad.runModal()
            return askAlarm(title, old)        // 고친 값을 잃지 않게 다시 묻는다
        }
        return a
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
                notify(L("ciFail"), body, subtitle: subtitle, sound: config.soundFail,
                       kind: .fail, url: r.ciUrl.isEmpty ? r.url : r.ciUrl)
            } else if r.ci == "success",
                      ["running", "pending", "created"].contains(before), mode == "all" {
                notify(L("ciOk"), body, subtitle: subtitle, sound: config.soundOK,
                       kind: .ok, url: r.ciUrl.isEmpty ? r.url : r.ciUrl)
            } else if ["running", "pending", "created"].contains(r.ci),
                      !["running", "pending", "created"].contains(before), mode == "all" {
                notify(L("ciRun"), body, subtitle: subtitle, sound: config.soundRun,
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
                    theme: theme, sound: sound, onClick: {
            if let url, let u = URL(string: url) { NSWorkspace.shared.open(u) }
        })
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
        let alarm = NSColor.systemPink
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
            case "alarm":
                // 안 끈 알림만 종으로 남긴다 — 끄면 사라진다
                if alarmPending > 0 { sep(); add("🔔\(alarmPending)", pal.alarm) }
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

        if out.length == 0 {
            if lastFetchOK && fetchedAt != nil {
                add(L("allClear"), pal.ok)          // 진짜로 할 일이 없을 때
            } else {
                add("Tally", .labelColor)           // 조회 전이거나 실패했을 때
            }
        }
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
        reanchorSoon()
        updateAgentCheck()
        // 데모용 인스턴스(MW_DIR)에서는 문서 스크린샷을 찍을 수 있게 좌표를 남긴다
        if ProcessInfo.processInfo.environment["MW_DIR"] != nil {
            log("창 번호 \(panel.windowNumber)  프레임 \(panel.frame)")
            if let f = statusItem.button?.window?.frame { log("메뉴바 아이콘 \(f)") }
        }
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
        updateLookMenu()
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

// 설정한 소리만 들어보기: ./tally --sound-test
if CommandLine.arguments.contains("--sound-test") {
    let w = Widget()
    let items = [("성공", w.config.soundOK), ("실패", w.config.soundFail),
                 ("시작", w.config.soundRun)]
    for (i, (label, name)) in items.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.4) {
            print("\(label): \(name.isEmpty ? "(무음)" : name)")
            Banner.audition(name)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) { exit(0) }
    NSApplication.shared.run()
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

// 알림 파일이 제대로 읽히는지 확인: ./tally --alarms
if CommandLine.arguments.contains("--alarms") {
    let w = Widget()
    Strings.lang = w.config.lang
    let now = Date()
    print("지금  \(now)")
    for (i, raw) in loadAlarmLines().enumerated() {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") { continue }
        guard let a = parseAlarm(raw, src: i) else {
            print("✗ 못 읽음  \(t)")
            continue
        }
        let every: String
        switch a.every {
        case .day: every = "매일"
        case .week: every = "매주 \(a.weekdays.sorted())"
        case .month: every = "매월 \(a.day)일"
        case .year: every = "매년 \(a.month)/\(a.day)"
        case .once: every = "한 번 \(a.year)/\(a.month)/\(a.day)"
        }
        let next = nextAlarmTime(a, after: now).map { "\($0)" } ?? "없음"
        let last = lastAlarmTime(a, before: now).map { "\($0)" } ?? "없음"
        print("✓ \(a.on ? "켜짐" : "꺼짐")  \(every)  \(String(format: "%02d:%02d", a.hour, a.minute))"
              + "  소리=\(a.sound.isEmpty ? "기본" : a.sound)  다시=\(a.snooze)분  \(a.title)")
        print("    지난 회차 \(last)")
        print("    다음 회차 \(next)")
        print("    다시 쓰면 → \(alarmLine(a))")
        if let again = parseAlarm(alarmLine(a), src: i) {
            let same = again.every == a.every && again.hour == a.hour && again.minute == a.minute
                && again.title == a.title && again.on == a.on && again.sound == a.sound
                && again.snooze == a.snooze && again.weekdays == a.weekdays && again.day == a.day
            print("    되읽기 \(same ? "같음 ✓" : "달라짐 ✗")")
        } else {
            print("    되읽기 실패 ✗")
        }
    }
    exit(0)
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
