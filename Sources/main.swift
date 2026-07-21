import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftTerm
import UniformTypeIdentifiers

// MARK: - Localization

/// Tiny EN/ES string table. Language comes from ~/.config/agent-notch/lang
/// ("en"/"es", set in the settings panel), defaulting to the system language.
enum L10n {
    static var lang = "en"
    static func refresh() {
        let cfg = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/lang")
        if let v = (try? String(contentsOf: cfg, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines), ["en", "es"].contains(v) {
            lang = v
        } else {
            lang = (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "es" : "en"
        }
    }
    // key: [english, spanish]
    private static let table: [String: [String]] = [
        "settings": ["Settings…", "Configuración…"],
        "quit": ["Quit Agent Notch", "Salir de Agent Notch"],
        "no_sessions": ["No recent agent sessions", "Sin sesiones recientes de agentes"],
        "shortcut_hint": ["Shortcuts: ⌃⌥N panel · ⌃⌥⇧T terminal · ⌘D split",
                          "Atajos: ⌃⌥N panel · ⌃⌥⇧T terminal · ⌘D dividir"],
        "terminal": ["Notch terminal (⌃⌥⇧T)", "Terminal del notch (⌃⌥⇧T)"],
        "zoom_pct": ["Hover zoom (%):", "Zoom al pasar el mouse (%):"],
        "gif_search": ["Search GIFs online:", "Buscar GIFs en internet:"],
        "search": ["Search", "Buscar"],
        "gif_for": ["for", "para"],
        "giphy_key": ["GIPHY API key:", "API key de GIPHY:"],
        "giphy_missing": ["GIPHY API key required", "Falta la API key de GIPHY"],
        "giphy_missing_info": ["Get a free key at developers.giphy.com (create an app, type: API) and paste it in the settings field.",
                               "Conseguí una key gratis en developers.giphy.com (creá una app, tipo API) y pegala en el campo de configuración."],
        "gif_search_fail": ["GIF search failed — check the API key and your connection.",
                            "Falló la búsqueda de GIFs — revisá la API key y tu conexión."],
        "gif_dl_fail": ["Could not download that GIF", "No se pudo descargar ese GIF"],
        "language": ["Language:", "Idioma:"],
        "codex_pet": ["Codex pet:", "Pet de Codex:"],
        "gif_title": ["Custom animated GIF (replaces the mascot while working):",
                      "GIF animado personalizado (reemplaza la mascota mientras trabaja):"],
        "choose": ["Choose…", "Elegir…"],
        "remove": ["Remove", "Quitar"],
        "none": ["— none —", "— ninguno —"],
        "save": ["Save", "Guardar"],
        "sounds_title": ["Sounds:", "Sonidos:"],
        "sound_done": ["When an agent finishes", "Cuando un agente termina"],
        "sound_attention": ["When an agent awaits your input", "Cuando un agente espera tu respuesta"],
        "settings_title": ["Agent Notch Plus — Settings", "Agent Notch Plus — Configuración"],
        "bad_gif": ["Could not read that GIF", "No se pudo leer ese GIF"],
        "bad_gif_info": ["The file does not look like a valid animated GIF.",
                         "El archivo no parece un GIF animado válido."],
        "choose_gif_msg": ["Choose an animated GIF for the mascot", "Elegí un GIF animado para la mascota"],
        "subagents": ["subagents", "subagentes"],
        "subagent": ["subagent", "subagente"],
        "you": ["You: ", "Vos: "],
    ]
    static func t(_ key: String) -> String { table[key]?[lang == "es" ? 1 : 0] ?? key }
}
func L(_ key: String) -> String { L10n.t(key) }

// MARK: - Model

enum AgentKind: String { case claude = "Claude Code", codex = "Codex" }

struct AgentSession {
    let id: String
    let kind: AgentKind
    let title: String
    let snippet: String
    let model: String
    let lastModified: Date
    var prompt: String = ""
    var threadID: String = ""
    var parentID: String?
    var nickname: String?
    var children: [AgentSession] = []
    var isLive: Bool = false  // process alive (from discovery, never mtime)
    // last user/assistant entry — housekeeping writes (away_summary etc.)
    // bump the file mtime but must not count as activity
    var lastActivity: Date?
    // hybrid: busy = alive AND conversing; quiet-while-alive is idle, not done
    var isBusy: Bool { isLive && Date().timeIntervalSince(lastActivity ?? lastModified) < 30 }
    var anyLive: Bool { isLive || children.contains { $0.isLive } }
    var anyBusy: Bool { isBusy || children.contains { $0.isBusy } }
    var effectiveLastModified: Date { children.reduce(lastModified) { max($0, $1.lastModified) } }
}

// MARK: - Process discovery
// Ported from open-vibe-island's ActiveAgentProcessDiscovery: "a session IS a
// running agent process in a terminal." `ps` finds agent processes (a TTY is
// required, which excludes headless/background sessions), `lsof` maps each
// process to the transcript file it holds open. Liveness comes from the OS,
// never from transcript mtimes.

final class ProcessDiscovery {
    // Claude Code appends-and-closes its transcript, so lsof usually shows no
    // open jsonl for it — open-vibe-island falls back to the process cwd (and
    // claims by tty so a terminal maps to one session). Codex holds its
    // rollout file open, so the path route always works there.
    struct Snapshot { let kind: AgentKind; let transcriptPath: String?; let cwd: String? }

    // open-vibe-island uses 0.5s/0.2s here, but Process-spawn overhead under
    // heavy load (a codex swarm compiling) blows through 0.2s and every agent
    // reads as dead — so: generous budgets, and ONE batched lsof per poll.
    private static let psTimeout: TimeInterval = 2.0
    private static let lsofTimeout: TimeInterval = 2.0

    func liveTranscripts() -> [Snapshot] {
        guard let psOut = run("/bin/ps", ["-Ao", "pid=,ppid=,tty=,command="], timeout: Self.psTimeout) else { return [] }
        var candidates: [(pid: String, tty: String, kind: AgentKind)] = []
        for line in psOut.split(whereSeparator: \.isNewline) {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard parts.count == 4 else { continue }
            let pid = String(parts[0]), tty = String(parts[2])
            let command = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard tty != "??", !command.isEmpty else { continue }  // agent must be terminal-attached
            if isClaude(command) { candidates.append((pid, tty, .claude)) }
            else if isCodex(command) { candidates.append((pid, tty, .codex)) }
        }
        let chunks = lsofChunks(pids: candidates.map(\.pid))
        var out: [Snapshot] = []
        var claimed = Set<String>()
        for (pid, tty, kind) in candidates {
            guard let lsof = chunks[pid] else { continue }
            let cwd = workingDirectory(from: lsof)
            // Claude subagents run in .claude/worktrees/agent-*/ — they are
            // metadata on the parent session, not sessions of their own.
            if kind == .claude, let cwd, cwd.contains("/.claude/worktrees/agent-") { continue }
            switch kind {
            case .claude:
                let path = bestClaudeTranscript(in: lsof, cwd: cwd)
                guard path != nil || cwd != nil else { continue }
                // claim key: sessionID ?? tty ?? cwd — one session per terminal
                guard claimed.insert("claude:\(path ?? tty)").inserted else { continue }
                out.append(Snapshot(kind: kind, transcriptPath: path, cwd: cwd))
            case .codex:
                guard let path = bestCodexTranscript(in: lsof),
                      claimed.insert("codex:\(path)").inserted else { continue }
                out.append(Snapshot(kind: kind, transcriptPath: path, cwd: cwd))
            }
        }
        return out
    }

    /// One lsof for all pids; -Fn output is split per-pid on its `p<pid>` markers.
    private func lsofChunks(pids: [String]) -> [String: String] {
        guard !pids.isEmpty,
              let outText = run("/usr/sbin/lsof", ["-a", "-p", pids.joined(separator: ","), "-Fn"], timeout: Self.lsofTimeout) else { return [:] }
        var chunks: [String: String] = [:]
        var curPid: String?
        var cur = ""
        for line in outText.split(whereSeparator: \.isNewline) {
            if line.first == "p" {
                if let p = curPid { chunks[p] = cur }
                curPid = String(line.dropFirst())
                cur = ""
            } else {
                cur += line + "\n"
            }
        }
        if let p = curPid { chunks[p] = cur }
        return chunks
    }

    private func isClaude(_ command: String) -> Bool {
        let lowered = command.lowercased()
        if lowered.contains("/.local/bin/claude") { return true }
        guard let first = lowered.split(separator: " ").first.map(String.init) else { return false }
        return first == "claude" || first.hasSuffix("/claude")
    }

    private func isCodex(_ command: String) -> Bool {
        let lowered = command.lowercased()
        guard let first = lowered.split(separator: " ").first.map(String.init) else { return false }
        return first == "codex" || first.hasSuffix("/codex") || lowered.contains("/codex/codex")
    }

    private func workingDirectory(from lsof: String) -> String? {
        let lines = lsof.split(whereSeparator: \.isNewline).map(String.init)
        for i in lines.indices where lines[i] == "fcwd" && lines.indices.contains(i + 1) {
            let next = lines[i + 1]
            guard next.first == "n" else { continue }
            let v = String(next.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if v.hasPrefix("/") { return v }
        }
        return nil
    }

    private func paths(in lsof: String, containing fragment: String) -> [String] {
        lsof.split(whereSeparator: \.isNewline).compactMap {
            guard $0.first == "n" else { return nil }
            let v = String($0.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return v.contains(fragment) && v.hasSuffix(".jsonl") ? v : nil
        }
    }

    private func bestClaudeTranscript(in lsof: String, cwd: String?) -> String? {
        let all = paths(in: lsof, containing: "/.claude/projects/")
        // a claude process can hold several project transcripts open; prefer
        // the one whose encoded project dir matches the process cwd
        if all.count > 1, let cwd {
            let encoded = cwd.replacingOccurrences(of: "/", with: "-")
            if let preferred = all.first(where: { $0.contains(encoded) }) { return preferred }
        }
        return all.first
    }

    private func bestCodexTranscript(in lsof: String) -> String? {
        // rollout filenames embed a timestamp, so the max name is the newest
        paths(in: lsof, containing: "/.codex/sessions/").max {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
                < URL(fileURLWithPath: $1).deletingPathExtension().lastPathComponent
        }
    }

    private func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            group.leave()
        }
        guard group.wait(timeout: .now() + timeout) == .success else { p.terminate(); return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Session scanning

final class SessionScanner {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// `live` = transcript paths held open by a running agent process;
    /// `claudeCwdCounts` = encoded-project-dir → number of claude processes
    /// with that cwd (the fallback when claude exposes no open transcript).
    /// Together they are the sole source of truth for isRunning.
    func scan(live: Set<String>, claudeCwdCounts: [String: Int]) -> [AgentSession] {
        let recent: (AgentSession) -> Bool = { $0.isLive || Date().timeIntervalSince($0.lastModified) < 6 * 3600 }
        var sessions = scanClaude(live: live, cwdCounts: claudeCwdCounts).filter(recent)
            + groupCodex(scanCodex(live: live).filter(recent))
        sessions.sort { $0.effectiveLastModified > $1.effectiveLastModified }
        return sessions
    }

    /// Fold Codex subagent rollouts under their root thread as children.
    private func groupCodex(_ nodes: [AgentSession]) -> [AgentSession] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.threadID, $0) })
        func rootKey(_ n: AgentSession) -> String {
            var cur = n, hops = 0
            while let p = cur.parentID, hops < 10 {
                guard let parent = byID[p] else { return p }  // parent aged out: group under its id anyway
                cur = parent; hops += 1
            }
            return cur.threadID
        }
        var groups: [String: [AgentSession]] = [:]
        for n in nodes { groups[rootKey(n), default: []].append(n) }
        var out: [AgentSession] = []
        for (key, members) in groups {
            var parent = byID[key] ?? members.sorted { $0.lastModified > $1.lastModified }[0]
            var kids = members.filter { $0.threadID != parent.threadID }
            kids.sort { $0.lastModified > $1.lastModified }
            // One codex process serves the whole thread group but holds only
            // its most recently opened rollout fd — so liveness observed on
            // any member means the shared process is alive for all of them.
            if parent.isLive || kids.contains(where: { $0.isLive }) {
                parent.isLive = true
                for i in kids.indices { kids[i].isLive = true }
            }
            parent.children = kids
            out.append(parent)
        }
        return out
    }

    private func scanClaude(live: Set<String>, cwdCounts: [String: Int]) -> [AgentSession] {
        var out: [AgentSession] = []
        let root = home.appendingPathComponent(".claude/projects")
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return out }
        for proj in projects {
            guard let files = try? fm.contentsOfDirectory(at: proj, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            var dated: [(URL, Date)] = files.compactMap { f in
                guard f.pathExtension == "jsonl",
                      let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return (f, m)
            }
            dated.sort { $0.1 > $1.1 }
            // cwd fallback: N claude processes in this project dir make its N
            // newest transcripts live (claude keeps no transcript fd open)
            let liveByCwd = cwdCounts[proj.lastPathComponent] ?? 0
            for (idx, (f, mtime)) in dated.enumerated() {
                let projName = proj.lastPathComponent.split(separator: "-").last.map(String.init) ?? proj.lastPathComponent
                let info = tailInfo(of: f)
                var sess = AgentSession(id: f.path, kind: .claude, title: projName,
                                        snippet: info.snippet, model: info.model, lastModified: mtime)
                sess.prompt = info.prompt
                sess.lastActivity = info.activity
                sess.isLive = live.contains(f.path) || idx < liveByCwd
                sess.children = claudeSubagents(sessionFile: f, parentLive: sess.isLive)
                out.append(sess)
            }
        }
        return out
    }

    private func scanCodex(live: Set<String>) -> [AgentSession] {
        var out: [AgentSession] = []
        let root = home.appendingPathComponent(".codex/sessions")
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return out }
        for case let f as URL in en where f.pathExtension == "jsonl" {
            guard let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            // Skip old files early to avoid reading them
            if Date().timeIntervalSince(mtime) > 6 * 3600 { continue }
            let meta = codexMeta(of: f)
            let info = tailInfo(of: f)
            var sess = AgentSession(id: f.path, kind: .codex, title: meta.title,
                                    snippet: info.snippet, model: info.model, lastModified: mtime)
            sess.prompt = info.prompt
            sess.isLive = live.contains(f.path)
            sess.threadID = meta.id
            sess.parentID = meta.parentID
            sess.nickname = meta.nickname
            out.append(sess)
        }
        return out
    }

    /// Claude Code subagent transcripts live in <proj>/<session-uuid>/subagents/agent-*.jsonl
    private func claudeSubagents(sessionFile f: URL, parentLive: Bool) -> [AgentSession] {
        let dir = f.deletingPathExtension().appendingPathComponent("subagents")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var kids: [AgentSession] = []
        for c in files where c.pathExtension == "jsonl" {
            guard let mtime = (try? c.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(mtime) < 6 * 3600 else { continue }
            let info = tailInfo(of: c)
            var kid = AgentSession(id: c.path, kind: .claude, title: "subagent",
                                   snippet: info.snippet, model: info.model, lastModified: mtime)
            // no nicknames here — label with the task it was given
            kid.nickname = info.prompt.isEmpty ? L("subagent") : String(info.prompt.prefix(40))
            // subagents share the parent process (open-vibe-island tracks them
            // as parent metadata) — liveness inherits, busyness from writes
            kid.isLive = parentLive
            kid.lastActivity = info.activity
            kids.append(kid)
        }
        return kids.sorted { $0.lastModified > $1.lastModified }
    }

    private func codexMeta(of file: URL) -> (title: String, id: String, parentID: String?, nickname: String?) {
        guard let fh = try? FileHandle(forReadingFrom: file) else { return ("Codex", file.path, nil, nil) }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 262_144)
        guard let line = String(data: head, encoding: .utf8)?.split(separator: "\n").first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return ("Codex", file.path, nil, nil) }
        let title = ((payload["cwd"] as? String).map { ($0 as NSString).lastPathComponent }) ?? "Codex"
        let id = (payload["id"] as? String) ?? file.path
        let parentID = payload["parent_thread_id"] as? String
        let nickname = (((payload["source"] as? [String: Any])?["subagent"] as? [String: Any])?["thread_spawn"] as? [String: Any])?["agent_nickname"] as? String
        return (title, id, parentID, nickname)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Read the tail of a jsonl transcript: last human-readable text + model
    /// name + timestamp of the last conversational (user/assistant) entry.
    private func tailInfo(of file: URL) -> (snippet: String, model: String, prompt: String, activity: Date?) {
        guard let fh = try? FileHandle(forReadingFrom: file) else { return ("", "", "", nil) }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let readLen: UInt64 = min(size, 131_072)
        try? fh.seek(toOffset: size - readLen)
        guard let data = try? fh.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return ("", "", "", nil) }
        var snippet = "", model = "", prompt = ""
        var activity: Date?
        for line in text.split(separator: "\n").reversed() {
            if model.isEmpty, let r = line.range(of: #""model":"([^"]+)""#, options: .regularExpression) {
                model = String(line[r].dropFirst(9).dropLast(1))
                model = model.replacingOccurrences(of: "claude-", with: "")
            }
            if snippet.isEmpty || prompt.isEmpty || activity == nil,
               let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                if snippet.isEmpty, let s = extractText(obj) { snippet = s }
                if prompt.isEmpty, let p = extractUserPrompt(obj) { prompt = p }
                // "system" entries (away_summary, compaction notes…) are
                // housekeeping, not activity
                if activity == nil, let ty = obj["type"] as? String,
                   ty == "user" || ty == "assistant",
                   let ts = obj["timestamp"] as? String {
                    activity = Self.isoParser.date(from: ts)
                }
            }
            if !snippet.isEmpty && !model.isEmpty && !prompt.isEmpty && activity != nil { break }
        }
        if model.isEmpty, size > readLen {
            // model can appear only early in long transcripts — check the head too
            try? fh.seek(toOffset: 0)
            if let head = try? fh.read(upToCount: 65_536),
               let headText = String(data: head, encoding: .utf8),
               let r = headText.range(of: #""model":"([^"]+)""#, options: .regularExpression) {
                model = String(headText[r].dropFirst(9).dropLast(1))
                    .replacingOccurrences(of: "claude-", with: "")
            }
        }
        return (snippet, model, prompt, activity)
    }

    /// The user's own message, if this line is one.
    private func extractUserPrompt(_ obj: [String: Any]) -> String? {
        // Codex: {"payload":{"type":"user_message","message":"..."}}
        if let payload = obj["payload"] as? [String: Any],
           payload["type"] as? String == "user_message",
           let m = payload["message"] as? String { return clean(m) }
        // Claude: {"type":"user","message":{"content":"..." | [{"type":"text","text":...}]}}
        if obj["type"] as? String == "user", let msg = obj["message"] as? [String: Any] {
            if let c = msg["content"] as? String { return clean(c) }
            if let arr = msg["content"] as? [[String: Any]] {
                for part in arr where part["type"] as? String == "text" {
                    if let t = part["text"] as? String { return clean(t) }
                }
            }
        }
        return nil
    }

    private func extractText(_ obj: [String: Any]) -> String? {
        // Claude: {"message": {"content": [{"type":"text","text":...}] | "..."}}
        var content: Any? = nil
        if let msg = obj["message"] as? [String: Any] { content = msg["content"] }
        // Codex: {"payload": {"content": [...]}} or nested message
        if content == nil, let payload = obj["payload"] as? [String: Any] {
            content = payload["content"] ?? (payload["message"] as? [String: Any])?["content"]
        }
        if let s = content as? String { return clean(s) }
        if let arr = content as? [[String: Any]] {
            for part in arr.reversed() {
                if let t = part["text"] as? String { return clean(t) }
            }
        }
        return nil
    }

    private func clean(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("<") || t.hasPrefix("{") { return nil }  // skip system-reminder / tool json
        t = t.replacingOccurrences(of: "\n", with: " ")
        if t.count > 90 { t = String(t.prefix(90)) + "…" }
        return t
    }
}

// MARK: - Custom GIF animations

/// An animated GIF chosen in the Configuración panel that replaces the
/// built-in mascot for an agent. Frames advance from the shared `t` clock.
final class GifAnimation {
    private let rep: NSBitmapImageRep
    private let frames: Int
    private let delay: Double
    let aspect: CGFloat

    init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let rep = NSBitmapImageRep(data: data),
              let n = (rep.value(forProperty: .frameCount) as? NSNumber)?.intValue, n > 0
        else { return nil }
        self.rep = rep
        self.frames = n
        let d = (rep.value(forProperty: .currentFrameDuration) as? NSNumber)?.doubleValue ?? 0.1
        self.delay = max(d, 0.02)
        self.aspect = CGFloat(rep.pixelsWide) / CGFloat(max(1, rep.pixelsHigh))
    }

    func draw(in rect: NSRect, t: CGFloat, alpha: CGFloat = 1) {
        rep.setProperty(.currentFrame, withValue: NSNumber(value: Int(Double(t) / delay) % frames))
        _ = rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha,
                     respectFlipped: false, hints: nil)
    }
}

// MARK: - Dither theme views

/// Row icon: mini mascot / Codex pet while running, green pixel checkmark when done.
final class DitherIconView: NSView {
    var running = false
    var idle = false  // alive but quiet: dim, static
    var kind: AgentKind = .claude
    var color: NSColor = .systemBlue  // kept for tint fallbacks
    var t: CGFloat = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 16) }

    static let checkmark: [(Int, Int)] = [
        (6, 1), (5, 2), (4, 3), (0, 3), (1, 4), (3, 4), (2, 5)
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if !running && !idle {
            // done: green pixel checkmark
            let cell: CGFloat = 2.2
            for (x, y) in Self.checkmark {
                ctx.setFillColor(NSColor.systemGreen.cgColor)
                ctx.fill(CGRect(x: 1 + CGFloat(x) * cell, y: 1 + CGFloat(7 - y) * cell,
                                width: cell - 0.4, height: cell - 0.4))
            }
            return
        }
        let alpha: CGFloat = idle ? 0.4 : 1.0
        if let gif = (kind == .claude ? IndicatorView.claudeGif : IndicatorView.codexGif) {
            gif.draw(in: NSRect(x: 1, y: 0, width: min(20, 16 * gif.aspect), height: 16),
                     t: idle ? 0 : t, alpha: alpha)
            return
        }
        if kind == .codex, let sprite = IndicatorView.codexSprite {
            let fw: CGFloat = 192, fh: CGFloat = 208
            let idx = idle ? 0 : Int(t / 0.12) % 8
            let src = NSRect(x: CGFloat(idx) * fw, y: 1872 - 2 * fh, width: fw, height: fh)
            NSGraphicsContext.current?.imageInterpolation = .none
            sprite.draw(in: NSRect(x: 1, y: 0, width: 16 * fw / fh, height: 16),
                        from: src, operation: .sourceOver, fraction: alpha)
            return
        }
        // mini Claude mascot walking, with a visible bob (static + dim when idle)
        let subW: CGFloat = 1.0, subH: CGFloat = 2.0
        let walk = idle ? 0 : Int(t * 2.5)
        let frame = IndicatorView.mascotFrames[walk % 2]
        let rows = frame.count * 2
        let y0 = CGFloat(rows) * subH + 1 + (walk % 2 == 0 ? 0 : 1.5)
        for (j, line) in frame.enumerated() {
            for (i, ch) in line.enumerated() {
                guard let q = IndicatorView.quadrants[ch] else { continue }
                let cells = [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)]
                for (on, qx, qy) in cells where on {
                    ctx.setFillColor(IndicatorView.claudeOrange.withAlphaComponent(alpha).cgColor)
                    ctx.fill(CGRect(x: CGFloat(i * 2 + qx) * subW,
                                    y: y0 - CGFloat(j * 2 + qy + 1) * subH,
                                    width: subW - 0.2, height: subH - 0.3))
                }
            }
        }
    }
}

/// A sparse row of gray pixels — the dithered stand-in for a separator line.
final class DitherSeparator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cell: CGFloat = 2
        var x: CGFloat = 0
        var seed: UInt64 = 0x9E3779B9
        while x < bounds.width {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = CGFloat(seed >> 33 & 0xFFFF) / 65535
            if r > 0.55 {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.06 + 0.10 * r).cgColor)
                ctx.fill(CGRect(x: x, y: 1, width: cell - 0.4, height: cell - 0.4))
            }
            x += cell
        }
    }
}

// MARK: - Session list popover

final class SessionListController: NSViewController {
    var sessions: [AgentSession] = [] { didSet { rebuild() } }
    // hover zoom: snippets get extra lines (same font size), so the bigger
    // panel shows MORE text, not bigger text
    var zoomFactor: CGFloat = 1 { didSet { if zoomFactor != oldValue { rebuild() } } }
    var onLayoutChange: (() -> Void)?
    private let stack = NSStackView()
    private var icons: [DitherIconView] = []
    private var animTimer: Timer?
    private var expandedIDs = Set<String>()

    override func loadView() {
        let v = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        view = v
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        icons.removeAll()
        if sessions.isEmpty {
            stack.addArrangedSubview(label(L("no_sessions"), size: 12, color: .secondaryLabelColor, bold: false))
            return
        }
        for (i, s) in sessions.prefix(6).enumerated() {
            if i > 0 {
                let sep = DitherSeparator()
                sep.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
            }
            stack.addArrangedSubview(row(for: s))
            if !s.children.isEmpty {
                let open = expandedIDs.contains(s.id)
                let btn = NSButton(title: "\(open ? "▾" : "▸") \(s.children.count) \(s.children.count == 1 ? L("subagent") : L("subagents"))",
                                   target: self, action: #selector(toggleChildren(_:)))
                btn.isBordered = false
                btn.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
                btn.contentTintColor = .systemBlue
                btn.identifier = NSUserInterfaceItemIdentifier(s.id)
                let wrap = NSStackView(views: [btn])
                wrap.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
                stack.addArrangedSubview(wrap)
                if open {
                    for child in s.children.prefix(8) {
                        stack.addArrangedSubview(childRow(for: child))
                    }
                }
            }
        }
        if animTimer == nil {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                guard let self else { return }
                for icon in self.icons { icon.t += 0.12 }
            }
        }
    }

    @objc private func toggleChildren(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        rebuild()
        onLayoutChange?()
    }

    private func childRow(for s: AgentSession) -> NSView {
        let icon = DitherIconView()
        icon.running = s.isBusy
        icon.idle = s.isLive && !s.isBusy
        icon.kind = s.kind
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        icons.append(icon)
        let name = label(s.nickname ?? (s.title.isEmpty ? s.kind.rawValue : s.title), size: 11, color: .secondaryLabelColor, bold: true)
        let tag = label("\(s.model.isEmpty ? s.kind.rawValue : s.model) · \(relative(s.lastModified))", size: 9,
                        color: (s.isBusy ? NSColor.systemBlue : s.isLive ? .secondaryLabelColor : .systemGreen).withAlphaComponent(0.6), bold: false)
        tag.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [icon, name, NSView(), tag])
        top.orientation = .horizontal
        top.translatesAutoresizingMaskIntoConstraints = false
        var views: [NSView] = [top]
        if !s.snippet.isEmpty {
            let snip = label(s.snippet, size: 11, color: .secondaryLabelColor, bold: false)
            snip.maximumNumberOfLines = zoomFactor > 1 ? 3 : 1
            snip.widthAnchor.constraint(lessThanOrEqualToConstant: 400 * zoomFactor).isActive = true
            views.append(snip)
        }
        let col = NSStackView(views: views)
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 1
        col.edgeInsets = NSEdgeInsets(top: 2, left: 28, bottom: 2, right: 4)
        top.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -32).isActive = true
        return col
    }

    var contentHeight: CGFloat {
        stack.fittingSize.height
    }

    private func row(for s: AgentSession) -> NSView {
        let icon = DitherIconView()
        icon.running = s.anyBusy
        icon.idle = s.anyLive && !s.anyBusy
        icon.kind = s.kind
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        icons.append(icon)
        let title = label(s.kind.rawValue, size: 12, color: .labelColor, bold: true)
        let tag = label("\(s.model.isEmpty ? s.title : s.model) · \(relative(s.lastModified))", size: 10,
                        color: (s.anyBusy ? NSColor.systemBlue : s.anyLive ? .secondaryLabelColor : .systemGreen).withAlphaComponent(0.75), bold: false)
        tag.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [icon, title, NSView(), tag])
        top.orientation = .horizontal
        top.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [top]
        let line = s.prompt.isEmpty ? s.snippet : L("you") + s.prompt
        if !line.isEmpty {
            let snippet = label(line, size: 11, color: .secondaryLabelColor, bold: false)
            snippet.maximumNumberOfLines = zoomFactor > 1 ? 4 : 1
            snippet.widthAnchor.constraint(lessThanOrEqualToConstant: 440 * zoomFactor).isActive = true
            views.append(snippet)
        }
        let col = NSStackView(views: views)
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 1
        col.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        top.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -8).isActive = true
        return col
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        // Truncate rather than force the window wider than its frame
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

// MARK: - Notch window content

/// Indicator content: branded pixel animations for whichever agents are running.
enum AgentGlyphState { case inactive, running, done }

final class IndicatorView: NSView {
    var claudeState: AgentGlyphState = .inactive { didSet { needsDisplay = true } }
    var codexState: AgentGlyphState = .inactive { didSet { needsDisplay = true } }
    var t: CGFloat = 0 { didSet { needsDisplay = true } }

    static let claudeOrange = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // Anthropic coral
    static let codexTeal = NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)     // OpenAI teal

    // The Claude Code launch-banner mascot, drawn from its real block characters.
    // Two frames: the feet alternate so it walks.
    static let mascotFrames: [[String]] = [
        [" ▐▛███▜▌ ",
         "▝▜█████▛▘",
         "  ▘▘ ▝▝  "],
        [" ▐▛███▜▌ ",
         "▝▜█████▛▘",
         "  ▝▝ ▘▘  "],
    ]
    // quadrant bits: (upper-left, upper-right, lower-left, lower-right)
    static let quadrants: [Character: (Bool, Bool, Bool, Bool)] = [
        "█": (true, true, true, true),
        "▐": (false, true, false, true),
        "▌": (true, false, true, false),
        "▛": (true, true, true, false),
        "▜": (true, true, false, true),
        "▙": (true, false, true, true),
        "▟": (false, true, true, true),
        "▘": (true, false, false, false),
        "▝": (false, true, false, false),
        "▖": (false, false, true, false),
        "▗": (false, false, false, true),
        " ": (false, false, false, false),
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cy = bounds.midY
        var x = bounds.maxX - 6  // right-aligned toward the notch
        // each agent keeps its own slot: mascot while running, green blob when
        // freshly done (cleared once you revisit the terminal)
        switch claudeState {
        case .running: x = drawClaudeRunning(ctx, right: x, cy: cy) - 6
        case .done: drawGreenBlob(ctx, right: x, cy: cy); x -= 24
        case .inactive: break
        }
        switch codexState {
        case .running: _ = drawCodexPet(ctx, right: x, cy: cy)
        case .done: drawGreenBlob(ctx, right: x, cy: cy)
        case .inactive: break
        }
    }

    private func drawGreenBlob(_ ctx: CGContext, right: CGFloat, cy: CGFloat) {
        let cell: CGFloat = 2.5, grid = 7
        let c = CGFloat(grid) / 2
        let step = Int(t * 2)
        let x0 = right - CGFloat(grid) * cell
        for i in 0..<grid {
            for j in 0..<grid {
                let dx = CGFloat(i) + 0.5 - c, dy = CGFloat(j) + 0.5 - c
                let dist = sqrt(dx * dx + dy * dy)
                let n = sin(CGFloat(i * 374761 + j * 668265 + step * 982451) * 0.0001) * 43758.5453
                let r = n - n.rounded(.down)
                guard r > 0.1 + dist / c * 0.8 else { continue }
                ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.5 + 0.5 * r).cgColor)
                ctx.fill(CGRect(x: x0 + CGFloat(i) * cell, y: cy - CGFloat(grid) * cell / 2 + CGFloat(j) * cell,
                                width: cell - 0.5, height: cell - 0.5))
            }
        }
    }

    /// Returns the left edge of what was drawn.
    private func drawCrab(_ ctx: CGContext, right: CGFloat, cy: CGFloat) -> CGFloat {
        // terminal cells are ~2x taller than wide — keep that aspect or he squishes
        let subW: CGFloat = 1.6, subH: CGFloat = 3.2
        let walk = Int(t * 2.5)
        let frame = Self.mascotFrames[walk % 2]
        let cols = frame[0].count * 2, rows = frame.count * 2
        let x0 = right - CGFloat(cols) * subW
        let bob: CGFloat = (walk % 2 == 0) ? -0.5 : 0.5  // little bounce, symmetric around center
        let y0 = cy + CGFloat(rows) * subH / 2 + bob - 2  // feet row is sparse; nudge down so the body reads centered
        let step = Int(t * 3)
        for (j, line) in frame.enumerated() {
            for (i, ch) in line.enumerated() {
                guard let q = Self.quadrants[ch] else { continue }
                let cells = [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)]
                for (on, qx, qy) in cells where on {
                    let n = sin(CGFloat(i * 374761 + j * 668265 + (qx + qy * 2) * 97 + step * 982451) * 0.0001) * 43758.5453
                    let r = n - n.rounded(.down)
                    // feet stay solid; body shimmers gently
                    let isFeet = j == frame.count - 1
                    let alpha = isFeet ? 1.0 : 0.8 + 0.2 * r
                    ctx.setFillColor(Self.claudeOrange.withAlphaComponent(alpha).cgColor)
                    ctx.fill(CGRect(x: x0 + CGFloat(i * 2 + qx) * subW,
                                    y: y0 - CGFloat(j * 2 + qy + 1) * subH,
                                    width: subW - 0.3, height: subH - 0.4))
                }
            }
        }
        return x0
    }

    // Official Codex pet spritesheets (8 cols x 9 rows, 192x208 frames);
    // row 1 is the "running-right" animation, 8 frames @ 120 ms.
    // The pet is chosen by ~/.config/agent-notch/pet (codex, dewey, fireball,
    // rocky, seedy, stacky, bsod, null-signal).
    static var currentPetID = "codex"
    private static var spriteCache: [String: NSImage] = [:]
    static var codexSprite: NSImage? {
        if let img = spriteCache[currentPetID] { return img }
        // pets/ lives next to the binary; the old Documents/GitHub clone is the fallback
        let exeDir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = [
            exeDir.appendingPathComponent("pets/pet-\(currentPetID).webp").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/GitHub/agent-notch/pets/pet-\(currentPetID).webp").path,
        ]
        for path in candidates {
            if let img = NSImage(contentsOfFile: path) {
                spriteCache[currentPetID] = img
                return img
            }
        }
        return nil
    }
    static func refreshPetChoice() {
        let cfg = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/pet")
        if let id = try? String(contentsOf: cfg, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            currentPetID = id
        }
    }

    // Custom GIF overrides (Configuración panel): ~/.config/agent-notch/{claude,codex}-gif
    // hold a path to an animated GIF that replaces that agent's mascot.
    static var claudeGif: GifAnimation?
    static var codexGif: GifAnimation?
    private static var claudeGifPath = ""
    private static var codexGifPath = ""
    static func refreshCustomGifs() {
        func readCfg(_ name: String) -> String {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/agent-notch/\(name)")
            return (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let cp = readCfg("claude-gif")
        if cp != claudeGifPath { claudeGifPath = cp; claudeGif = cp.isEmpty ? nil : GifAnimation(path: cp) }
        let xp = readCfg("codex-gif")
        if xp != codexGifPath { codexGifPath = xp; codexGif = xp.isEmpty ? nil : GifAnimation(path: xp) }
    }

    /// Claude slot: custom GIF if configured, else the built-in walking mascot.
    private func drawClaudeRunning(_ ctx: CGContext, right: CGFloat, cy: CGFloat) -> CGFloat {
        if let gif = Self.claudeGif {
            let h: CGFloat = 26, w = h * gif.aspect
            let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
            gif.draw(in: dest, t: t)
            return dest.minX
        }
        return drawCrab(ctx, right: right, cy: cy)
    }

    private func drawCodexPet(_ ctx: CGContext, right: CGFloat, cy: CGFloat) -> CGFloat {
        if let gif = Self.codexGif {
            let h: CGFloat = 26, w = h * gif.aspect
            let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
            gif.draw(in: dest, t: t)
            return dest.minX
        }
        guard let sprite = Self.codexSprite else {
            return drawRing(ctx, right: right, cy: cy, color: Self.codexTeal)
        }
        let fw: CGFloat = 192, fh: CGFloat = 208
        let idx = Int(t / 0.12) % 8
        let src = NSRect(x: CGFloat(idx) * fw, y: 1872 - 2 * fh, width: fw, height: fh)
        let h: CGFloat = 26, w = h * fw / fh
        let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
        NSGraphicsContext.current?.imageInterpolation = .none  // keep the pixel art crisp
        sprite.draw(in: dest, from: src, operation: .sourceOver, fraction: 1)
        return dest.minX
    }

    /// Returns the left edge of what was drawn.
    private func drawRing(_ ctx: CGContext, right: CGFloat, cy: CGFloat, color: NSColor) -> CGFloat {
        let cell: CGFloat = 2.5, grid = 9
        let x0 = right - CGFloat(grid) * cell
        let y0 = cy - CGFloat(grid) * cell / 2
        let c = CGFloat(grid) / 2
        let phase = t * 1.4
        let step = Int(t * 3)
        for i in 0..<grid {
            for j in 0..<grid {
                let dx = CGFloat(i) + 0.5 - c
                let dy = CGFloat(j) + 0.5 - c
                let dist = sqrt(dx * dx + dy * dy)
                guard dist > c - 2.4, dist < c else { continue }
                var angle = atan2(dy, dx) - phase
                angle = angle - (angle / (2 * .pi)).rounded(.down) * 2 * .pi
                let intensity = 1 - angle / (2 * .pi)
                let n = sin(CGFloat(i * 374761 + j * 668265 + step * 982451) * 0.0001) * 43758.5453
                let r = n - n.rounded(.down)
                let a = intensity * intensity * (0.55 + 0.45 * r)
                guard a > 0.08 else { continue }
                ctx.setFillColor(color.withAlphaComponent(a).cgColor)
                ctx.fill(CGRect(x: x0 + CGFloat(i) * cell, y: y0 + CGFloat(j) * cell,
                                width: cell - 0.5, height: cell - 0.5))
            }
        }
        return x0
    }
}

/// Borderless panel that can take keyboard focus (for the notch terminal).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Thin grab bar at the top of the notch terminal: drag to move the window.
final class TermDragStrip: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w: CGFloat = 36
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: bounds.midX - w / 2, y: bounds.midY - 1.5, width: w, height: 3))
    }
}

final class NotchView: NSView {
    var expanded = false { didSet { needsDisplay = true } }
    var barHeight: CGFloat = 32
    var onCollapse: (() -> Void)?
    var onSettings: (() -> Void)?
    var onTerminal: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { onCollapse?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func openTerminal() { onTerminal?() }
    override func rightMouseUp(with event: NSEvent) {
        let menu = NSMenu()
        let term = NSMenuItem(title: L("terminal"), action: #selector(openTerminal), keyEquivalent: "")
        term.target = self
        menu.addItem(term)
        let cfg = NSMenuItem(title: L("settings"), action: #selector(openSettings), keyEquivalent: "")
        cfg.target = self
        menu.addItem(cfg)
        menu.addItem(NSMenuItem(title: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        if expanded {
            // Black panel with rounded bottom corners, only when open
            let r: CGFloat = 16
            let path = NSBezierPath()
            path.move(to: NSPoint(x: b.minX, y: b.maxY))
            path.line(to: NSPoint(x: b.minX, y: b.minY + r))
            path.appendArc(withCenter: NSPoint(x: b.minX + r, y: b.minY + r), radius: r, startAngle: 180, endAngle: 270, clockwise: false)
            path.line(to: NSPoint(x: b.maxX - r, y: b.minY))
            path.appendArc(withCenter: NSPoint(x: b.maxX - r, y: b.minY + r), radius: r, startAngle: 270, endAngle: 0, clockwise: false)
            path.line(to: NSPoint(x: b.maxX, y: b.maxY))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return  // no spinner while the panel is open
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var indicatorWindow: NSWindow!
    private let notchView = NotchView()
    private let indicatorView = IndicatorView()
    private let scanner = SessionScanner()
    private let discovery = ProcessDiscovery()
    private let scanQueue = DispatchQueue(label: "agent-notch.scan", qos: .utility)
    // open-vibe-island removal rule: a transcript's process must be missing
    // for 2 consecutive polls (~6 s) before its session stops being live
    private var missCounts: [String: Int] = [:]
    private let listController = SessionListController()
    private var frame = 0
    private var claudeWasLive = false
    private var codexWasLive = false
    private var claudeState: AgentGlyphState = .inactive
    private var codexState: AgentGlyphState = .inactive
    private var expanded = false
    private var hotKeyRef: EventHotKeyRef?
    private var hoverTicks = 0
    private var hoverOpened = false  // opened by hover → auto-close on mouse-leave
    private var zoomed = false       // sticky-open panel grows 25% under the mouse
    private var soundDone = false
    private var soundAttention = false
    private var claudePrevBusy = false
    private var codexPrevBusy = false
    private var settingsWindow: NSWindow?
    private var claudeGifLabel: NSTextField?
    private var codexGifLabel: NSTextField?
    private var claudePreview: NSImageView?
    private var codexPreview: NSImageView?
    private var petPopupRef: NSPopUpButton?
    private var langPopupRef: NSPopUpButton?
    private var soundDoneRef: NSButton?
    private var soundAttRef: NSButton?
    private var pendClaudeGif = ""   // settings are staged; applied on Save
    private var pendCodexGif = ""
    private var pendZoomField: NSTextField?
    private var zoomPct: CGFloat = 25   // hover-zoom percentage (config "zoom")
    private var hotKeyRef2: EventHotKeyRef?
    // one sound per episode: armed while busy, disarmed once played
    private var claudeDoneArmed = false, claudeAttArmed = false
    private var codexDoneArmed = false, codexAttArmed = false
    private var lastSoundAt = Date.distantPast
    private var termWindow: NSPanel?
    private var termSplit: NSSplitView?
    private var termViews: [LocalProcessTerminalView] = []
    private var gifSearchField: NSTextField?
    private var gifTargetPopup: NSPopUpButton?
    private var giphyKeyField: NSTextField?
    private var gifResults: [(id: String, preview: URL, full: URL)] = []
    private var gifResultViews: [NSImageView] = []

    // Geometry
    private var screen: NSScreen { NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main! }
    private var notchWidth: CGFloat {
        let s = screen
        if #available(macOS 12.0, *), s.safeAreaInsets.top > 0,
           let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            return s.frame.width - left.width - right.width
        }
        return 180  // no physical notch: fake pill
    }
    private var barHeight: CGFloat {
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return 30
    }
    private let sidePad: CGFloat = 120  // indicator strip beside the notch
    private let expandedSize = NSSize(width: 480, height: 240)

    // In a fullscreen space the menu bar is hidden, so the bar can own the whole top edge
    private var isFullscreenSpace: Bool {
        screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }

    private func collapsedFrame() -> NSRect {
        // Always full-width: transparent and click-through, so it costs nothing,
        // and the indicator can dodge menu items anywhere along the bar
        let s = screen.frame
        return NSRect(x: s.minX, y: s.maxY - barHeight, width: s.width, height: barHeight)
    }

    /// Fixed spot just left of the notch.
    private var indicatorScreenX: CGFloat {
        let s = screen
        var notchLeftX = s.frame.midX - 90
        if #available(macOS 12.0, *), let left = s.auxiliaryTopLeftArea { notchLeftX = left.maxX }
        return notchLeftX - 36
    }
    private func expandedFrame() -> NSRect {
        let s = screen.frame
        // width scales by the configured zoom; height follows the content,
        // which grows because snippets unfold into multiple lines when zoomed
        let z: CGFloat = zoomed ? 1 + zoomPct / 100 : 1.0
        let w = max(expandedSize.width, notchWidth + sidePad * 2) * z
        let h = barHeight + max(60, listController.contentHeight) + 10
        return NSRect(x: s.midX - w / 2, y: s.maxY - h, width: w, height: h)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        L10n.refresh()
        readSoundPrefs()
        readZoomPref()

        // Panel window: full-width, mouse-transparent unless expanded
        window = NSWindow(contentRect: collapsedFrame(), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)  // panel is always black
        window.contentView = notchView
        notchView.wantsLayer = true
        notchView.barHeight = barHeight

        // Indicator window: tiny, always interactive, never steals focus
        indicatorWindow = NSPanel(contentRect: indicatorScreenRect,
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        indicatorWindow.isOpaque = false
        indicatorWindow.backgroundColor = .clear
        indicatorWindow.hasShadow = false
        indicatorWindow.level = .statusBar
        indicatorWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        indicatorWindow.ignoresMouseEvents = true  // visual only — clicks are caught by the global monitor
        indicatorWindow.contentView = indicatorView

        listController.onLayoutChange = { [weak self] in
            guard let self, self.expanded else { return }
            self.window.setFrame(self.expandedFrame(), display: true)
        }
        notchView.onCollapse = { [weak self] in
            guard let self, self.expanded else { return }
            self.setExpanded(false)
        }
        notchView.onSettings = { [weak self] in self?.showSettings() }
        notchView.onTerminal = { [weak self] in self?.toggleTerminal() }

        // Global hotkey ⌃⌥N toggles the panel. Carbon RegisterEventHotKey works
        // without Accessibility/Input-Monitoring permission, unlike key monitors.
        var keySpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if hkID.id == 2 {
                    me.toggleTerminal()
                } else {
                    me.hoverOpened = false
                    me.setExpanded(!me.expanded)
                }
            }
            return noErr
        }, 1, &keySpec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let panelKeyID = EventHotKeyID(signature: OSType(0x414E_4348), id: 1)  // 'ANCH'
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), panelKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        // ⌃⌥⇧T — plain ⌃⌥T collides with browser/tab shortcuts in some apps
        let termKeyID = EventHotKeyID(signature: OSType(0x414E_4348), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey | shiftKey), termKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef2)

        // ⌘D splits the notch terminal (local monitor: only our own windows)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let w = self.termWindow, e.window === w,
                  e.modifierFlags.contains(.command),
                  e.charactersIgnoringModifiers?.lowercased() == "d" else { return e }
            self.addTerminalPane()
            return nil
        }

        // Right-click on the indicator → settings menu (the indicator window
        // ignores mouse events, so this rides the same global-monitor route)
        NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            guard let self, !self.expanded else { return }
            let loc = NSEvent.mouseLocation
            guard self.indicatorScreenRect.insetBy(dx: -4, dy: 0).contains(loc) else { return }
            let menu = NSMenu()
            let term = NSMenuItem(title: L("terminal"), action: #selector(self.toggleTerminal), keyEquivalent: "")
            term.target = self
            menu.addItem(term)
            let cfg = NSMenuItem(title: L("settings"), action: #selector(self.showSettings), keyEquivalent: "")
            cfg.target = self
            menu.addItem(cfg)
            menu.addItem(NSMenuItem(title: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            menu.popUp(positioning: nil, at: loc, in: nil)
        }
        // The indicator window never takes mouse input (routing to tiny borderless
        // menu-bar windows is unreliable) — a global monitor catches its clicks,
        // and also handles click-away dismissal.
        var lastToggle = ProcessInfo.processInfo.systemUptime
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let now = ProcessInfo.processInfo.systemUptime
            if !self.expanded {
                if self.indicatorScreenRect.insetBy(dx: -4, dy: 0).contains(loc), now - lastToggle > 0.15 {
                    lastToggle = now
                    self.hoverOpened = false  // click-open is sticky, unlike hover-open
                    self.setExpanded(true)
                }
            } else if !self.window.frame.contains(loc) {
                self.setExpanded(false)
            }
        }
        window.orderFrontRegardless()
        indicatorWindow.orderFrontRegardless()

        // Revisiting the terminal acknowledges finished agents — green clears
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let terminals = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2",
                             "net.kovidgoyal.kitty", "dev.warp.Warp-Stable", "io.alacritty"]
            if terminals.contains(app.bundleIdentifier ?? "") {
                if self.claudeState == .done { self.claudeState = .inactive }
                if self.codexState == .done { self.codexState = .inactive }
                self.render()
            }
        }

        // SIGUSR1 toggles the panel — lets tests drive it without synthetic clicks
        let sig = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        sig.setEventHandler { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.expanded)
        }
        sig.resume()
        signal(SIGUSR1, SIG_IGN)
        self.sigSource = sig

        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        rescan()
        // 3 s poll cadence, matching open-vibe-island's process discovery
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in self?.rescan() }
    }

    /// Screen rect of the indicator — the only collapsed region that should catch clicks
    private var indicatorScreenRect: NSRect {
        NSRect(x: indicatorScreenX - 30, y: screen.frame.maxY - barHeight, width: 66, height: barHeight)
    }

    private func setExpanded(_ on: Bool) {
        guard expanded != on else { return }
        expanded = on
        zoomed = false
        listController.zoomFactor = 1
        // Attach the list only while expanded — its Auto Layout content would
        // otherwise force the borderless window wider than the collapsed frame.
        let listView = listController.view
        if on {
            notchView.expanded = true
            listView.translatesAutoresizingMaskIntoConstraints = false
            listView.alphaValue = 1
            notchView.addSubview(listView)
            NSLayoutConstraint.activate([
                listView.topAnchor.constraint(equalTo: notchView.topAnchor, constant: barHeight + 4),
                listView.leadingAnchor.constraint(equalTo: notchView.leadingAnchor, constant: 8),
                listView.trailingAnchor.constraint(equalTo: notchView.trailingAnchor, constant: -8),
            ])
        }
        // Never animate the window frame — macOS interpolates it unreliably.
        // Resize instantly while invisible and animate the content layer instead
        // (the technique used by boring.notch / NotchNook).
        if on {
            window.ignoresMouseEvents = false
            window.setFrame(expandedFrame(), display: true)
            indicatorWindow.orderOut(nil)  // spinner hides while the panel is open
            animatePanelLayer(open: true)
        } else {
            indicatorWindow.orderFrontRegardless()  // back immediately — never leave a dead zone
            window.ignoresMouseEvents = true
            animatePanelLayer(open: false) { [weak self] in
                guard let self, !self.expanded else { return }
                self.notchView.expanded = false
                listView.removeFromSuperview()
                self.window.setFrame(self.collapsedFrame(), display: true)
                self.indicatorWindow.orderFrontRegardless()
            }
        }
    }

    private var animating = false
    private var sigSource: DispatchSourceSignal?

    /// Scale + fade the content layer toward/away from the notch (top center).
    private func animatePanelLayer(open: Bool, completion: (() -> Void)? = nil) {
        guard let layer = notchView.layer else { completion?(); return }
        let b = notchView.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: b.midX, y: b.maxY)
        let small = CATransform3DMakeScale(0.25, 0.06, 1)
        let from = open ? small : CATransform3DIdentity
        let to = open ? CATransform3DIdentity : small
        animating = true
        // Set model values to the end state, then animate the presentation to match
        layer.transform = to
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.animating = false
            if !open {
                // window is about to shrink; restore the layer for next time
                layer.transform = CATransform3DIdentity
            }
            completion?()
        }
        let t = CABasicAnimation(keyPath: "transform")
        t.fromValue = NSValue(caTransform3D: from)
        t.toValue = NSValue(caTransform3D: to)
        t.duration = 0.22
        t.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
        layer.add(t, forKey: t.keyPath)
        CATransaction.commit()
    }

    private func rescan() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            // Process discovery is the authoritative liveness signal. Keys are
            // transcript paths, or "cwd#<encoded>#<i>" for claude's cwd fallback.
            var seen = Set<String>()
            var cwdIndex: [String: Int] = [:]
            for snap in self.discovery.liveTranscripts() {
                if let path = snap.transcriptPath {
                    seen.insert(path)
                } else if snap.kind == .claude, let cwd = snap.cwd {
                    let encoded = cwd.replacingOccurrences(of: "/", with: "-")
                    let i = cwdIndex[encoded, default: 0]
                    cwdIndex[encoded] = i + 1
                    seen.insert("cwd#\(encoded)#\(i)")
                }
            }
            for p in seen { self.missCounts[p] = 0 }
            for (p, n) in self.missCounts where !seen.contains(p) {
                if n + 1 >= 2 { self.missCounts.removeValue(forKey: p) } else { self.missCounts[p] = n + 1 }
            }
            var live = Set<String>()
            var cwdCounts: [String: Int] = [:]
            for key in self.missCounts.keys {
                if key.hasPrefix("cwd#") {
                    let encoded = String(key.dropFirst(4).split(separator: "#")[0])
                    cwdCounts[encoded, default: 0] += 1
                } else {
                    live.insert(key)
                }
            }
            let result = self.scanner.scan(live: live, claudeCwdCounts: cwdCounts)
            DispatchQueue.main.async {
                // Track fullscreen-space changes: full-width bar when the menu bar is hidden
                if !self.expanded, !self.animating {
                    if self.window.frame != self.collapsedFrame() {
                        self.window.setFrame(self.collapsedFrame(), display: true)
                    }
                    // re-dodge menu items as the frontmost app changes
                    let r = self.indicatorScreenRect
                    if self.indicatorWindow.frame != r { self.indicatorWindow.setFrame(r, display: true) }
                }
                IndicatorView.refreshPetChoice()
                IndicatorView.refreshCustomGifs()
                self.listController.sessions = result
                // busy → mascot; alive-but-quiet → nothing (idle, not done);
                // process exited → done blob (cleared on terminal focus)
                let claudeLive = result.contains { $0.kind == .claude && $0.anyLive }
                let claudeBusy = result.contains { $0.kind == .claude && $0.anyBusy }
                let codexLive = result.contains { $0.kind == .codex && $0.anyLive }
                let codexBusy = result.contains { $0.kind == .codex && $0.anyBusy }
                // sounds (settings): once per episode. An agent "arms" its
                // sounds while busy and each fires at most once until it gets
                // busy again — liveness flaps under load can't re-trigger them.
                if claudeBusy { self.claudeDoneArmed = true; self.claudeAttArmed = true }
                if codexBusy { self.codexDoneArmed = true; self.codexAttArmed = true }
                let claudeGone = self.claudeWasLive && !claudeLive
                let codexGone = self.codexWasLive && !codexLive
                let claudeWaits = self.claudePrevBusy && !claudeBusy && claudeLive
                let codexWaits = self.codexPrevBusy && !codexBusy && codexLive
                if self.soundDone,
                   (claudeGone && self.claudeDoneArmed) || (codexGone && self.codexDoneArmed) {
                    self.playSound("Glass")
                }
                if self.soundAttention,
                   (claudeWaits && self.claudeAttArmed) || (codexWaits && self.codexAttArmed) {
                    self.playSound("Ping")
                }
                if claudeGone { self.claudeDoneArmed = false; self.claudeAttArmed = false }
                if codexGone { self.codexDoneArmed = false; self.codexAttArmed = false }
                if claudeWaits { self.claudeAttArmed = false }
                if codexWaits { self.codexAttArmed = false }
                self.claudePrevBusy = claudeBusy
                self.codexPrevBusy = codexBusy
                self.claudeState = claudeBusy ? .running
                    : claudeLive ? .inactive
                    : (self.claudeWasLive ? .done : self.claudeState)
                self.codexState = codexBusy ? .running
                    : codexLive ? .inactive
                    : (self.codexWasLive ? .done : self.codexState)
                self.claudeWasLive = claudeLive
                self.codexWasLive = codexLive
                self.render()
            }
        }
    }

    private func tick() {
        frame += 1
        checkHover()
        render()
    }

    /// Hover peek: resting the cursor on the indicator (~0.35 s) opens the
    /// panel; it closes again once the mouse leaves it. Click/hotkey opens
    /// stay put until dismissed.
    private func checkHover() {
        let loc = NSEvent.mouseLocation
        if !expanded {
            if indicatorScreenRect.insetBy(dx: -4, dy: 0).contains(loc) {
                hoverTicks += 1
                if hoverTicks >= 3 {
                    hoverTicks = 0
                    hoverOpened = true
                    setExpanded(true)
                }
            } else { hoverTicks = 0 }
        } else if hoverOpened {
            if !window.frame.insetBy(dx: -24, dy: -24).contains(loc) {
                hoverOpened = false
                setExpanded(false)
            } else {
                setZoomed(window.frame.contains(loc))  // hover-opens zoom too
            }
        } else {
            // sticky opens (click/hotkey): hovering grows the panel
            setZoomed(window.frame.contains(loc))
        }
    }

    /// Grow the open panel 25% while the mouse is over it; shrink back when it
    /// leaves. Only for sticky opens — hover-opens already auto-dismiss.
    private func setZoomed(_ on: Bool) {
        guard expanded, zoomed != on, !animating else { return }
        zoomed = on
        listController.zoomFactor = on ? 1 + zoomPct / 100 : 1  // rebuilds with scaled text
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: on ? .easeOut : .easeIn)
            window.animator().setFrame(expandedFrame(), display: true)
        }
    }

    private func render() {
        indicatorView.claudeState = claudeState
        indicatorView.codexState = codexState
        indicatorView.t = CGFloat(frame) * 0.12
    }

    // MARK: - Notch terminal (SwiftTerm)

    /// A real terminal hanging from the notch — borderless, black, rounded
    /// bottom corners, always on top. ⌃⌥⇧T or the context menus toggle it:
    /// it unrolls from the notch like a curtain and rolls back up on hide,
    /// while the shells keep running in the background. ⌘D splits up to 3
    /// panes side by side. Run `claude` in one and its confirmations are
    /// answered right here in the notch.
    @objc fileprivate func toggleTerminal() {
        if let w = termWindow {
            if w.isVisible { hideTerminal(w) } else { showTerminal(w) }
            return
        }
        let s = screen.frame
        let tw: CGFloat = 760, th: CGFloat = 460
        let frame = NSRect(x: s.midX - tw / 2, y: s.maxY - barHeight - th, width: tw, height: th)
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 280)
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: tw, height: th)))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 16
        container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let stripH: CGFloat = 22
        let strip = TermDragStrip(frame: NSRect(x: 0, y: th - stripH, width: tw, height: stripH))
        strip.autoresizingMask = [.width, .minYMargin]
        let closeBtn = NSButton(title: "✕", target: self, action: #selector(forceCloseTerminal))
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 12, weight: .bold)
        closeBtn.contentTintColor = NSColor(white: 0.7, alpha: 1)
        closeBtn.frame = NSRect(x: 8, y: th - stripH, width: 20, height: stripH)
        closeBtn.autoresizingMask = [.minYMargin]
        let split = NSSplitView(frame: NSRect(x: 12, y: 12, width: tw - 24, height: th - stripH - 16))
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        container.addSubview(split)
        container.addSubview(strip)
        container.addSubview(closeBtn)
        panel.contentView = container
        termWindow = panel
        termSplit = split
        addTerminalPane()
        showTerminal(panel)
    }

    /// ⌘D: add another shell pane to the notch terminal (up to 3).
    @objc fileprivate func addTerminalPane() {
        guard let split = termSplit, termViews.count < 3 else { return }
        let term = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        term.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        term.nativeBackgroundColor = .black
        term.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        term.processDelegate = self
        split.addArrangedSubview(term)
        split.adjustSubviews()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        term.startProcess(executable: shell, args: ["-l"])
        termViews.append(term)
        termWindow?.makeFirstResponder(term)
    }

    private func showTerminal(_ panel: NSWindow) {
        // always re-anchor under the notch, keeping the user's chosen size
        let s = screen.frame
        var f = panel.frame
        f.origin.x = s.midX - f.width / 2
        f.origin.y = s.maxY - barHeight - f.height
        panel.setFrame(f, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        curtain(panel, open: true)
    }

    private func hideTerminal(_ panel: NSWindow) {
        curtain(panel, open: false) { panel.orderOut(nil) }
    }

    /// Curtain animation: unroll down from the notch / roll back up into it.
    private func curtain(_ panel: NSWindow, open: Bool, completion: (() -> Void)? = nil) {
        guard let view = panel.contentView, let layer = view.layer else { completion?(); return }
        let b = view.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: b.midX, y: b.maxY)
        let rolled = CATransform3DMakeScale(1, 0.02, 1)
        layer.transform = open ? CATransform3DIdentity : rolled
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion?()
            if !open { layer.transform = CATransform3DIdentity }
        }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: open ? rolled : CATransform3DIdentity)
        a.toValue = NSValue(caTransform3D: open ? CATransform3DIdentity : rolled)
        a.duration = 0.28
        a.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
        layer.add(a, forKey: "curtain")
        CATransaction.commit()
    }

    /// Full close: kills every shell (✕ button, hung shells) and discards the
    /// window so the next ⌃⌥⇧T starts fresh.
    @objc fileprivate func forceCloseTerminal() {
        for t in termViews { t.terminate() }
        termViews.removeAll()
        termWindow?.orderOut(nil)
        termWindow = nil
        termSplit = nil
    }

    // MARK: - Settings panel

    @objc fileprivate func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.close()  // rebuild fresh so staged values start from disk

        func cfg(_ name: String) -> String {
            (try? String(contentsOf: configURL(name), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        pendClaudeGif = cfg("claude-gif")
        pendCodexGif = cfg("codex-gif")

        func row(_ title: String, _ views: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            let r = NSStackView(views: [l] + views)
            r.orientation = .horizontal
            r.spacing = 8
            return r
        }
        func preview() -> NSImageView {
            let iv = NSImageView()
            iv.animates = true  // NSImageView plays animated GIFs on its own
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.backgroundColor = NSColor.black.cgColor
            iv.layer?.cornerRadius = 6
            iv.widthAnchor.constraint(equalToConstant: 72).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return iv
        }

        let hint = NSTextField(labelWithString: L("shortcut_hint"))
        hint.textColor = .secondaryLabelColor

        let langPopup = NSPopUpButton()
        langPopup.addItems(withTitles: ["English", "Español"])
        langPopup.selectItem(at: L10n.lang == "es" ? 1 : 0)
        langPopupRef = langPopup

        let petPopup = NSPopUpButton()
        petPopup.addItems(withTitles: ["codex", "dewey", "fireball", "rocky", "seedy", "stacky", "bsod", "null-signal"])
        petPopup.selectItem(withTitle: IndicatorView.currentPetID)
        petPopupRef = petPopup

        let zoomField = NSTextField(string: String(Int(zoomPct)))
        zoomField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        pendZoomField = zoomField
        let zoomPctLabel = NSTextField(labelWithString: "%")
        zoomPctLabel.textColor = .secondaryLabelColor

        let gifTitle = NSTextField(labelWithString: L("gif_title"))
        gifTitle.font = .systemFont(ofSize: 12, weight: .semibold)

        claudeGifLabel = pathLabel(pendClaudeGif)
        codexGifLabel = pathLabel(pendCodexGif)
        claudePreview = preview()
        codexPreview = preview()
        setPreview(claudePreview, path: pendClaudeGif)
        setPreview(codexPreview, path: pendCodexGif)

        let targetPopup = NSPopUpButton()
        targetPopup.addItems(withTitles: ["Claude", "Codex"])
        gifTargetPopup = targetPopup
        let searchField = NSTextField(string: "")
        searchField.placeholderString = "pixel cat…"
        searchField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        gifSearchField = searchField
        let keyField = NSTextField(string: cfg("giphy-key"))
        keyField.placeholderString = "developers.giphy.com"
        keyField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        giphyKeyField = keyField
        let resultsRow = NSStackView()
        resultsRow.orientation = .horizontal
        resultsRow.spacing = 6
        gifResults = []
        gifResultViews = (0..<6).map { i in
            let iv = NSImageView()
            iv.animates = true
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.backgroundColor = NSColor.black.cgColor
            iv.layer?.cornerRadius = 6
            iv.widthAnchor.constraint(equalToConstant: 76).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 56).isActive = true
            iv.tag = i
            iv.isHidden = true
            iv.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(gifResultClicked(_:))))
            resultsRow.addArrangedSubview(iv)
            return iv
        }

        let soundDoneCheck = NSButton(checkboxWithTitle: L("sound_done"), target: nil, action: nil)
        soundDoneCheck.state = soundDone ? .on : .off
        soundDoneRef = soundDoneCheck
        let soundAttCheck = NSButton(checkboxWithTitle: L("sound_attention"), target: nil, action: nil)
        soundAttCheck.state = soundAttention ? .on : .off
        soundAttRef = soundAttCheck
        let soundCol = NSStackView(views: [soundDoneCheck, soundAttCheck])
        soundCol.orientation = .vertical
        soundCol.alignment = .leading
        soundCol.spacing = 4

        let saveBtn = NSButton(title: L("save"), target: self, action: #selector(saveSettings))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        let saveRow = NSStackView(views: [NSView(), saveBtn])
        saveRow.orientation = .horizontal

        let stack = NSStackView(views: [
            hint,
            row(L("language"), [langPopup]),
            row(L("codex_pet"), [petPopup]),
            row(L("zoom_pct"), [zoomField, zoomPctLabel]),
            gifTitle,
            row("Claude:", [claudeGifLabel!, button(L("choose"), #selector(chooseClaudeGif)),
                            button(L("remove"), #selector(clearClaudeGif)), claudePreview!]),
            row("Codex:", [codexGifLabel!, button(L("choose"), #selector(chooseCodexGif)),
                           button(L("remove"), #selector(clearCodexGif)), codexPreview!]),
            row(L("gif_search"), [searchField, button(L("search"), #selector(searchGifs)),
                                  NSTextField(labelWithString: L("gif_for")), targetPopup]),
            row(L("giphy_key"), [keyField]),
            resultsRow,
            row(L("sounds_title"), [soundCol]),
            saveRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 300),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("settings_title")
        w.isReleasedWhenClosed = false
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        saveRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
    }

    @objc private func saveSettings() {
        writeConfig("claude-gif", pendClaudeGif)
        writeConfig("codex-gif", pendCodexGif)
        if let id = petPopupRef?.titleOfSelectedItem { writeConfig("pet", id) }
        writeConfig("lang", langPopupRef?.indexOfSelectedItem == 1 ? "es" : "en")
        writeConfig("sound-done", soundDoneRef?.state == .on ? "1" : "")
        writeConfig("sound-attention", soundAttRef?.state == .on ? "1" : "")
        let pct = Int(min(100, max(0, Double(pendZoomField?.stringValue ?? "") ?? 25)))
        writeConfig("zoom", String(pct))
        writeConfig("giphy-key", giphyKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        L10n.refresh()
        readSoundPrefs()
        readZoomPref()
        IndicatorView.refreshPetChoice()
        IndicatorView.refreshCustomGifs()
        settingsWindow?.close()
        settingsWindow = nil
    }

    private func readSoundPrefs() {
        soundDone = FileManager.default.fileExists(atPath: configURL("sound-done").path)
        soundAttention = FileManager.default.fileExists(atPath: configURL("sound-attention").path)
    }

    /// Extra belt-and-suspenders: never chime more than once per 5 s.
    private func playSound(_ name: String) {
        guard Date().timeIntervalSince(lastSoundAt) > 5 else { return }
        lastSoundAt = Date()
        NSSound(named: name)?.play()
    }

    private func readZoomPref() {
        let v = (try? String(contentsOf: configURL("zoom"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        zoomPct = CGFloat(min(100, max(0, Double(v ?? "") ?? 25)))
    }

    private func pathLabel(_ path: String) -> NSTextField {
        let l = NSTextField(labelWithString: path.isEmpty ? L("none") : (path as NSString).lastPathComponent)
        l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingMiddle
        l.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
        return l
    }

    private func setPreview(_ iv: NSImageView?, path: String) {
        iv?.image = path.isEmpty ? nil : NSImage(contentsOfFile: path)
    }

    // MARK: - Online GIF search (GIPHY)
    // The ONLY network access in the app, and only when the user hits Search.

    @objc private func searchGifs() {
        let key = giphyKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { alert(L("giphy_missing"), L("giphy_missing_info")); return }
        let q = gifSearchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !q.isEmpty else { return }
        var comps = URLComponents(string: "https://api.giphy.com/v1/gifs/search")!
        comps.queryItems = [URLQueryItem(name: "api_key", value: key), URLQueryItem(name: "q", value: q),
                            URLQueryItem(name: "limit", value: "6"), URLQueryItem(name: "rating", value: "g")]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, _ in
            var found: [(id: String, preview: URL, full: URL)] = []
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["data"] as? [[String: Any]] {
                for it in items {
                    guard let id = it["id"] as? String,
                          let imgs = it["images"] as? [String: Any],
                          let pv = ((imgs["fixed_height_small"] as? [String: Any])?["url"] as? String)
                              .flatMap(URL.init(string:)),
                          let full = ((imgs["original"] as? [String: Any])?["url"] as? String)
                              .flatMap(URL.init(string:))
                    else { continue }
                    found.append((id, pv, full))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard !found.isEmpty else { self.alert(L("gif_search_fail"), ""); return }
                self.gifResults = found
                for (i, iv) in self.gifResultViews.enumerated() {
                    guard i < found.count else { iv.isHidden = true; continue }
                    iv.isHidden = false
                    iv.image = nil
                    URLSession.shared.dataTask(with: found[i].preview) { d, _, _ in
                        guard let d, let img = NSImage(data: d) else { return }
                        DispatchQueue.main.async { iv.image = img }
                    }.resume()
                }
                if let w = self.settingsWindow, let content = w.contentView {
                    w.setContentSize(content.fittingSize)
                }
            }
        }.resume()
    }

    /// Click on a result: download it and stage it for the chosen agent.
    @objc private func gifResultClicked(_ g: NSClickGestureRecognizer) {
        guard let iv = g.view as? NSImageView, iv.tag < gifResults.count else { return }
        let r = gifResults[iv.tag]
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/gifs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("giphy-\(r.id).gif")
        URLSession.shared.dataTask(with: r.full) { [weak self] d, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let d, (try? d.write(to: dest)) != nil, GifAnimation(path: dest.path) != nil else {
                    self.alert(L("gif_dl_fail"), "")
                    return
                }
                if self.gifTargetPopup?.indexOfSelectedItem == 1 {
                    self.pendCodexGif = dest.path
                    self.codexGifLabel?.stringValue = dest.lastPathComponent
                    self.setPreview(self.codexPreview, path: dest.path)
                } else {
                    self.pendClaudeGif = dest.path
                    self.claudeGifLabel?.stringValue = dest.lastPathComponent
                    self.setPreview(self.claudePreview, path: dest.path)
                }
            }
        }.resume()
    }

    private func alert(_ msg: String, _ info: String) {
        let a = NSAlert()
        a.messageText = msg
        a.informativeText = info
        a.runModal()
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }

    private func configURL(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agent-notch/\(name)")
    }

    private func writeConfig(_ name: String, _ value: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agent-notch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if value.isEmpty { try? FileManager.default.removeItem(at: configURL(name)) }
        else { try? value.write(to: configURL(name), atomically: true, encoding: .utf8) }
    }

    @objc private func chooseClaudeGif() { chooseGif(claude: true) }
    @objc private func chooseCodexGif() { chooseGif(claude: false) }
    @objc private func clearClaudeGif() {
        pendClaudeGif = ""
        claudeGifLabel?.stringValue = L("none")
        setPreview(claudePreview, path: "")
    }
    @objc private func clearCodexGif() {
        pendCodexGif = ""
        codexGifLabel?.stringValue = L("none")
        setPreview(codexPreview, path: "")
    }

    /// Stages the choice (applied on Save) and shows it in the animated preview.
    private func chooseGif(claude: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.message = L("choose_gif_msg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard GifAnimation(path: url.path) != nil else {
            let a = NSAlert()
            a.messageText = L("bad_gif")
            a.informativeText = L("bad_gif_info")
            a.runModal()
            return
        }
        if claude {
            pendClaudeGif = url.path
            claudeGifLabel?.stringValue = url.lastPathComponent
            setPreview(claudePreview, path: url.path)
        } else {
            pendCodexGif = url.path
            codexGifLabel?.stringValue = url.lastPathComponent
            setPreview(codexPreview, path: url.path)
        }
    }
}

extension AppDelegate: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    /// A shell ended (`exit`, crash, kill) — remove its pane; when the last
    /// one goes, close the notch terminal.
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let t = source as? LocalProcessTerminalView, let idx = self.termViews.firstIndex(of: t) {
                self.termViews.remove(at: idx)
                t.removeFromSuperview()
                self.termSplit?.adjustSubviews()
            }
            if self.termViews.isEmpty { self.forceCloseTerminal() }
        }
    }
}

// Debug: `./AgentNotch --scan` prints one discovery + scan cycle and exits.
if CommandLine.arguments.contains("--scan") {
    let snaps = ProcessDiscovery().liveTranscripts()
    print("== process discovery ==")
    for s in snaps { print("\(s.kind.rawValue): path=\(s.transcriptPath ?? "nil") cwd=\(s.cwd ?? "nil")") }
    var live = Set<String>()
    var cwdCounts: [String: Int] = [:]
    for s in snaps {
        if let p = s.transcriptPath { live.insert(p) }
        else if s.kind == .claude, let c = s.cwd { cwdCounts[c.replacingOccurrences(of: "/", with: "-"), default: 0] += 1 }
    }
    print("== sessions ==")
    for s in SessionScanner().scan(live: live, claudeCwdCounts: cwdCounts) {
        print("\(s.kind.rawValue) [\(s.title)] live=\(s.isLive) busy=\(s.isBusy) mtime=\(-s.lastModified.timeIntervalSinceNow)s kids=\(s.children.count)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
