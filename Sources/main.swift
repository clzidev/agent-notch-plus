import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Quartz
import ServiceManagement
import SwiftTerm
import UniformTypeIdentifiers

let appVersion = "2.9.0"
let projectURL = "https://github.com/clzidev/agent-notch-plus"

/// A pending question/permission request from an agent, written by the
/// Claude Code hook into ~/.config/agent-notch/asks/<session>.json.
struct AgentAsk {
    let sessionID: String
    let message: String   // the notification text / permission summary
    let cwd: String
    let tty: String       // set by the app from process discovery, for replies
    let time: Date
}

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
        "cancel": ["Cancel", "Cancelar"],
        "quit_confirm": ["Quit Agent Notch Plus?", "¿Salir de Agent Notch Plus?"],
        "quit_confirm_info": ["The notch, indicator and any open terminal will close.",
                              "Se cerrarán el notch, el indicador y cualquier terminal abierta."],
        "no_sessions": ["No recent agent sessions", "Sin sesiones recientes de agentes"],
        "sessions": ["sessions", "sesiones"],
        "active": ["active", "activas"],
        "st_working": ["Working…", "Trabajando…"],
        "st_waiting": ["Waiting for you", "Esperando tu respuesta"],
        "st_done": ["Done ✓", "Terminado ✓"],
        "asking": ["Needs your answer", "Necesita tu respuesta"],
        "reply_ph": ["Type your reply and press ↩", "Escribí tu respuesta y ↩"],
        "send": ["Send", "Enviar"],
        "focus_term": ["Focus terminal", "Ir a la terminal"],
        "install_hook": ["Enable notch replies (install hook)", "Activar respuestas del notch (instalar hook)"],
        "uninstall_hook": ["Disable notch replies (remove hook)", "Desactivar respuestas del notch (quitar hook)"],
        "replies_title": ["Reply from the notch:", "Responder desde el notch:"],
        "hook_ok": ["Hook installed", "Hook instalado"],
        "hook_ok_info": ["Claude Code will now notify the notch when an agent asks for input. Restart running Claude sessions to pick it up.",
                         "Claude Code ahora avisará al notch cuando un agente pida datos. Reiniciá las sesiones de Claude abiertas para que lo tomen."],
        "hook_off": ["Hook removed", "Hook quitado"],
        "hook_off_info": ["The notch will no longer be notified of agent questions.",
                          "El notch ya no será avisado de las preguntas de los agentes."],
        "ext_inject": ["Reply to external terminals (needs Accessibility)",
                       "Responder a terminales externas (requiere Accesibilidad)"],
        "ext_inject_info": ["This reply targets a terminal outside the notch. Enable \"Reply to external terminals\" in settings and grant Accessibility — note keystrokes go to the focused window.",
                            "Esta respuesta va a una terminal fuera del notch. Activá \"Responder a terminales externas\" en la configuración y otorgá Accesibilidad — ojo que las teclas van a la ventana enfocada."],
        "shortcut_hint": ["Every shortcut below is configurable (⌘-keys work inside the terminal).",
                          "Todos los atajos de abajo son configurables (las teclas ⌘ funcionan dentro de la terminal)."],
        "panel_hotkey": ["Panel shortcut:", "Atajo del panel:"],
        "term_keys": ["Terminal keys:", "Teclas de terminal:"],
        "key_split": ["split", "dividir"],
        "key_files": ["files", "archivos"],
        "key_folders": ["folders", "carpetas"],
        "terminal": ["Notch terminal", "Terminal del notch"],
        "term_hotkey": ["Terminal shortcut:", "Atajo de terminal:"],
        "term_dir": ["Terminal start folder:", "Carpeta inicial de la terminal:"],
        "term_size": ["Terminal size (% of screen):", "Tamaño de la terminal (% de pantalla):"],
        "panel_alpha": ["Panel opacity (%):", "Opacidad del panel (%):"],
        "term_alpha": ["Terminal opacity (%):", "Opacidad de la terminal (%):"],
        "choose_dir": ["Choose…", "Elegir…"],
        "clear_dir": ["Reset", "Quitar"],
        "project": ["Project:", "Proyecto:"],
        "gif_gallery": ["Open gallery…", "Abrir galería…"],
        "gallery_title": ["Animated Emoji Gallery", "Galería de emojis animados"],
        "gallery_hint": ["Google Noto animated emoji — no API or account needed. Search by name; click one to apply it instantly.",
                         "Emojis animados de Google (Noto) — sin API ni cuenta. Buscá por nombre; clic en uno para aplicarlo al instante."],
        "zoom_pct": ["Hover zoom (%):", "Zoom al pasar el mouse (%):"],
        "search": ["Search", "Buscar"],
        "gif_for": ["for", "para"],
        "gif_dl_fail": ["Could not download that animation", "No se pudo descargar esa animación"],
        "language": ["Language:", "Idioma:"],
        "codex_pet": ["Codex pet:", "Pet de Codex:"],
        "mascots": ["Animated mascots:", "Mascotas animadas:"],
        "preview": ["Preview (actual size):", "Vista previa (tamaño real):"],
        "startup": ["Startup:", "Inicio:"],
        "login_item": ["Launch at login", "Iniciar al iniciar la Mac"],
        "login_needs_app": ["Install the app first", "Primero instalá la app"],
        "login_needs_app_info": ["Launch at login needs the installed app: run scripts/build-app.sh and copy build/AgentNotchPlus.app to /Applications.",
                                 "Iniciar al arrancar requiere la app instalada: corré scripts/build-app.sh y copiá build/AgentNotchPlus.app a /Applications."],
        "restore_default": ["Restore original mascot", "Restaurar mascota original"],
        "save": ["Save", "Guardar"],
        "sounds_title": ["Sounds:", "Sonidos:"],
        "sound_done": ["When an agent finishes", "Cuando un agente termina"],
        "sound_attention": ["When an agent awaits your input", "Cuando un agente espera tu respuesta"],
        "settings_title": ["Agent Notch Plus — Settings", "Agent Notch Plus — Configuración"],
        "no_results": ["No matches", "Sin coincidencias"],
        "col_name": ["Name", "Nombre"],
        "col_modified": ["Modified", "Modificado"],
        "col_size": ["Size", "Tamaño"],
        "remove_fav": ["Remove from favorites", "Quitar de favoritos"],
        "subagents": ["subagents", "subagentes"],
        "subagent": ["subagent", "subagente"],
        "you": ["You: ", "Vos: "],
    ]
    static func t(_ key: String) -> String { table[key]?[lang == "es" ? 1 : 0] ?? key }
}
func L(_ key: String) -> String { L10n.t(key) }

// MARK: - Model

enum AgentKind: String { case claude = "Claude Code", codex = "Codex" }

/// Claude Code names a session's project dir by replacing EVERY
/// non-alphanumeric character with "-" (/Users/x/public_html →
/// -Users-x-public-html). Matching only "/" misses dirs with "_" or "." and
/// their sessions never read as live.
func encodeProjectDir(_ path: String) -> String {
    String(path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
}

/// Scale transform anchored at the top-center of `b` WITHOUT touching the
/// layer's anchorPoint. AppKit resets layer geometry (anchor/position) on
/// every layout pass, which used to send close/hide animations sliding off
/// to one side instead of shrinking into the notch.
func topAnchoredScale(_ sx: CGFloat, _ sy: CGFloat, _ b: NSRect) -> CATransform3D {
    var m = CATransform3DMakeTranslation(b.midX * (1 - sx), b.maxY * (1 - sy), 0)
    m = CATransform3DScale(m, sx, sy, 1)
    return m
}

/// Current working directory of a process (the terminal's shell), straight
/// from the kernel — how the quick-folders pane mirrors `cd` in real time.
func pidCwd(_ pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return withUnsafePointer(to: info.pvi_cdir.vip_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
}

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
    var cpu: Double = 0       // process %cpu — waiting at the prompt sits near 0
    // last user/assistant entry — housekeeping writes (away_summary etc.)
    // bump the file mtime but must not count as activity
    var lastActivity: Date?
    // busy = alive AND (recently wrote OR the process is visibly crunching:
    // long thinking writes nothing to the transcript but burns CPU, and a
    // finished turn stops burning CPU long before the 30 s write window ends)
    var isBusy: Bool { isLive && (cpu >= 8 || Date().timeIntervalSince(lastActivity ?? lastModified) < 20) }
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
    struct Snapshot { let kind: AgentKind; let transcriptPath: String?; let cwd: String?; let cpu: Double; let tty: String }

    // open-vibe-island uses 0.5s/0.2s here, but Process-spawn overhead under
    // heavy load (a codex swarm compiling) blows through 0.2s and every agent
    // reads as dead — so: generous budgets, and ONE batched lsof per poll.
    private static let psTimeout: TimeInterval = 2.0
    private static let lsofTimeout: TimeInterval = 2.0

    func liveTranscripts() -> [Snapshot] {
        guard let psOut = run("/bin/ps", ["-Ao", "pid=,ppid=,tty=,%cpu=,command="], timeout: Self.psTimeout) else { return [] }
        var candidates: [(pid: String, tty: String, cpu: Double, kind: AgentKind)] = []
        for line in psOut.split(whereSeparator: \.isNewline) {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard parts.count == 5 else { continue }
            let pid = String(parts[0]), tty = String(parts[2])
            let cpu = Double(String(parts[3]).replacingOccurrences(of: ",", with: ".")) ?? 0
            let command = String(parts[4]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard tty != "??", !command.isEmpty else { continue }  // agent must be terminal-attached
            if isClaude(command) { candidates.append((pid, tty, cpu, .claude)) }
            else if isCodex(command) { candidates.append((pid, tty, cpu, .codex)) }
        }
        let chunks = lsofChunks(pids: candidates.map(\.pid))
        var out: [Snapshot] = []
        var claimed = Set<String>()
        for (pid, tty, cpu, kind) in candidates {
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
                out.append(Snapshot(kind: kind, transcriptPath: path, cwd: cwd, cpu: cpu, tty: tty))
            case .codex:
                guard let path = bestCodexTranscript(in: lsof),
                      claimed.insert("codex:\(path)").inserted else { continue }
                out.append(Snapshot(kind: kind, transcriptPath: path, cwd: cwd, cpu: cpu, tty: tty))
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
            let encoded = encodeProjectDir(cwd)
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
    // transcript tails are re-read every 3 s poll — cache by mtime so only
    // files that actually changed get read again (the scan's biggest cost)
    private var tailCache: [String: (mtime: Date, info: (snippet: String, model: String, prompt: String, activity: Date?))] = [:]
    // a rollout's first line never changes — cache it forever
    private var codexMetaCache: [String: (title: String, id: String, parentID: String?, nickname: String?)] = [:]

    private func cachedTailInfo(of f: URL, mtime: Date) -> (snippet: String, model: String, prompt: String, activity: Date?) {
        if let c = tailCache[f.path], c.mtime == mtime { return c.info }
        let info = tailInfo(of: f)
        tailCache[f.path] = (mtime, info)
        return info
    }

    /// `live` = transcript paths held open by a running agent process;
    /// `claudeCwdCounts` = encoded-project-dir → number of claude processes
    /// with that cwd (the fallback when claude exposes no open transcript).
    /// Together they are the sole source of truth for isRunning.
    func scan(live: Set<String>, claudeCwdCounts: [String: Int],
              cpuByPath: [String: Double] = [:], cpuByCwd: [String: Double] = [:]) -> [AgentSession] {
        if tailCache.count > 600 { tailCache.removeAll() }        // unbounded-growth guard
        if codexMetaCache.count > 600 { codexMetaCache.removeAll() }
        let recent: (AgentSession) -> Bool = { $0.isLive || Date().timeIntervalSince($0.lastModified) < 6 * 3600 }
        var sessions = scanClaude(live: live, cwdCounts: claudeCwdCounts,
                                  cpuByPath: cpuByPath, cpuByCwd: cpuByCwd).filter(recent)
            + groupCodex(scanCodex(live: live, cpuByPath: cpuByPath).filter(recent))
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
            let maxCpu = max(parent.cpu, kids.map(\.cpu).max() ?? 0)
            parent.cpu = maxCpu
            for i in kids.indices { kids[i].cpu = maxCpu }
            parent.children = kids
            out.append(parent)
        }
        return out
    }

    private func scanClaude(live: Set<String>, cwdCounts: [String: Int],
                            cpuByPath: [String: Double], cpuByCwd: [String: Double]) -> [AgentSession] {
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
                let info = cachedTailInfo(of: f, mtime: mtime)
                var sess = AgentSession(id: f.path, kind: .claude, title: projName,
                                        snippet: info.snippet, model: info.model, lastModified: mtime)
                sess.prompt = info.prompt
                sess.lastActivity = info.activity
                sess.isLive = live.contains(f.path) || idx < liveByCwd
                sess.cpu = cpuByPath[f.path] ?? (idx < liveByCwd ? (cpuByCwd[proj.lastPathComponent] ?? 0) : 0)
                sess.children = claudeSubagents(sessionFile: f, parentLive: sess.isLive, parentCpu: sess.cpu)
                out.append(sess)
            }
        }
        return out
    }

    private func scanCodex(live: Set<String>, cpuByPath: [String: Double]) -> [AgentSession] {
        var out: [AgentSession] = []
        let root = home.appendingPathComponent(".codex/sessions")
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return out }
        for case let f as URL in en where f.pathExtension == "jsonl" {
            guard let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            // Skip old files early to avoid reading them
            if Date().timeIntervalSince(mtime) > 6 * 3600 { continue }
            let meta = codexMetaCache[f.path] ?? {
                let m = codexMeta(of: f)
                codexMetaCache[f.path] = m
                return m
            }()
            let info = cachedTailInfo(of: f, mtime: mtime)
            var sess = AgentSession(id: f.path, kind: .codex, title: meta.title,
                                    snippet: info.snippet, model: info.model, lastModified: mtime)
            sess.prompt = info.prompt
            sess.isLive = live.contains(f.path)
            sess.cpu = cpuByPath[f.path] ?? 0
            sess.threadID = meta.id
            sess.parentID = meta.parentID
            sess.nickname = meta.nickname
            out.append(sess)
        }
        return out
    }

    /// Claude Code subagent transcripts live in <proj>/<session-uuid>/subagents/agent-*.jsonl
    private func claudeSubagents(sessionFile f: URL, parentLive: Bool, parentCpu: Double) -> [AgentSession] {
        let dir = f.deletingPathExtension().appendingPathComponent("subagents")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var kids: [AgentSession] = []
        for c in files where c.pathExtension == "jsonl" {
            guard let mtime = (try? c.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(mtime) < 6 * 3600 else { continue }
            let info = cachedTailInfo(of: c, mtime: mtime)
            var kid = AgentSession(id: c.path, kind: .claude, title: "subagent",
                                   snippet: info.snippet, model: info.model, lastModified: mtime)
            // no nicknames here — label with the task it was given
            kid.nickname = info.prompt.isEmpty ? L("subagent") : String(info.prompt.prefix(40))
            // subagents share the parent process (open-vibe-island tracks them
            // as parent metadata) — liveness inherits, busyness from writes
            kid.isLive = parentLive
            kid.cpu = parentCpu
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
        // keep enough text to fill the zoomed panel's wrapped lines
        if t.count > 300 { t = String(t.prefix(300)) + "…" }
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
    // actual panel content width — text stretches to fill it instead of
    // leaving dead black space on the right
    var contentWidth: CGFloat = 480 { didSet { if contentWidth != oldValue { rebuild() } } }
    var onLayoutChange: (() -> Void)?
    var onSettings: (() -> Void)?
    var onTerminal: (() -> Void)?
    var asks: [AgentAsk] = [] { didSet { rebuild() } }
    var onReply: ((AgentAsk, String) -> Void)?
    var onFocusAsk: ((AgentAsk) -> Void)?
    private let stack = NSStackView()
    private var icons: [DitherIconView] = []
    private var animTimer: Timer?
    private var expandedIDs = Set<String>()

    override func loadView() {
        let v = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
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
        stack.addArrangedSubview(headerBar())
        for ask in asks.prefix(3) { stack.addArrangedSubview(askCard(ask)) }
        if sessions.isEmpty {
            stack.addArrangedSubview(label(L("no_sessions"), size: 12, color: .secondaryLabelColor, bold: false))
            return
        }
        for s in sessions.prefix(6) {
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
                // skip while the panel is detached — no point animating rows
                // nobody can see
                guard let self, self.view.window != nil else { return }
                for icon in self.icons { icon.t += 0.12 }
            }
        }
    }

    /// Top bar of the panel: quick actions on the left, session summary on
    /// the right — the panel is a small control center now, not just a list.
    private func headerBar() -> NSView {
        func hbtn(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.isBordered = false
            b.contentTintColor = .secondaryLabelColor
            b.font = .systemFont(ofSize: 15)
            return b
        }
        let busy = sessions.filter { $0.anyBusy }.count
        let summary = label("\(sessions.count) \(L("sessions")) · \(busy) \(L("active"))",
                            size: 10, color: .secondaryLabelColor, bold: false)
        let bar = NSStackView(views: [hbtn("⚙︎", #selector(hdrSettings)), hbtn("⌨︎", #selector(hdrTerminal)),
                                      NSView(), summary])
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return bar
    }
    @objc private func hdrSettings() { onSettings?() }
    @objc private func hdrTerminal() { onTerminal?() }

    /// A highlighted card for an agent waiting on you: the question, a reply
    /// field (↩ or Send), and a "focus terminal" shortcut.
    private func askCard(_ ask: AgentAsk) -> NSView {
        let title = label("🔔 " + L("asking"), size: 11, color: .systemOrange, bold: true)
        let proj = label(((ask.cwd as NSString).lastPathComponent), size: 10, color: .secondaryLabelColor, bold: false)
        let head = NSStackView(views: [title, NSView(), proj])
        head.orientation = .horizontal
        let msg = label(ask.message, size: 11, color: NSColor(white: 0.85, alpha: 1), bold: false,
                        lines: 3)
        msg.preferredMaxLayoutWidth = contentWidth - 28

        let field = NSTextField(string: "")
        field.placeholderString = L("reply_ph")
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.target = self
        field.action = #selector(replyFieldSubmit(_:))
        field.identifier = NSUserInterfaceItemIdentifier(ask.sessionID)
        replyFields[ask.sessionID] = (field, ask)
        let send = NSButton(title: L("send"), target: self, action: #selector(replyButton(_:)))
        send.bezelStyle = .rounded
        send.identifier = NSUserInterfaceItemIdentifier(ask.sessionID)
        let focus = NSButton(title: L("focus_term"), target: self, action: #selector(focusAskButton(_:)))
        focus.bezelStyle = .rounded
        focus.identifier = NSUserInterfaceItemIdentifier(ask.sessionID)
        let controls = NSStackView(views: [field, send, focus])
        controls.orientation = .horizontal
        controls.spacing = 6
        field.widthAnchor.constraint(equalToConstant: contentWidth - 190).isActive = true

        let col = NSStackView(views: [head, msg, controls])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 5
        col.translatesAutoresizingMaskIntoConstraints = false
        head.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.15, green: 0.1, blue: 0.02, alpha: 1).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.6).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            card.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        return card
    }

    private var replyFields: [String: (NSTextField, AgentAsk)] = [:]
    @objc private func replyFieldSubmit(_ f: NSTextField) { sendReply(id: f.identifier?.rawValue) }
    @objc private func replyButton(_ b: NSButton) { sendReply(id: b.identifier?.rawValue) }
    private func sendReply(id: String?) {
        guard let id, let (field, ask) = replyFields[id] else { return }
        let text = field.stringValue
        guard !text.isEmpty else { return }
        onReply?(ask, text)
    }
    @objc private func focusAskButton(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, let (_, ask) = replyFields[id] else { return }
        onFocusAsk?(ask)
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
            let snip = label(s.snippet, size: 11, color: .secondaryLabelColor, bold: false,
                             lines: zoomFactor >= 1.5 ? 3 : zoomFactor > 1 ? 2 : 1)
            let w = contentWidth - 36
            snip.preferredMaxLayoutWidth = w
            snip.widthAnchor.constraint(equalToConstant: w).isActive = true
            views.append(snip)
        }
        let col = NSStackView(views: views)
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 1
        col.edgeInsets = NSEdgeInsets(top: 2, left: 28, bottom: 2, right: 4)
        col.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        top.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -32).isActive = true
        return col
    }

    var contentHeight: CGFloat {
        stack.fittingSize.height
    }

    /// One session = one card: mascot, agent + project, model + age, the
    /// prompt/snippet, and a colored status line. The active session's card
    /// gets a warm highlighted border, vibe-island style.
    private func row(for s: AgentSession) -> NSView {
        let icon = DitherIconView()
        icon.running = s.anyBusy
        icon.idle = s.anyLive && !s.anyBusy
        icon.kind = s.kind
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        icons.append(icon)
        let title = label(s.kind.rawValue, size: 12, color: .labelColor, bold: true)
        let proj = label("· \(s.title)", size: 11, color: .secondaryLabelColor, bold: false)
        let tag = label("\(s.model.isEmpty ? "" : s.model + " · ")\(relative(s.effectiveLastModified))",
                        size: 10, color: .secondaryLabelColor, bold: false)
        tag.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [icon, title, proj, NSView(), tag])
        top.orientation = .horizontal
        top.spacing = 5
        top.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [top]
        let line = s.prompt.isEmpty ? s.snippet : L("you") + s.prompt
        let w = contentWidth - 28
        if !line.isEmpty {
            let snippet = label(line, size: 11, color: NSColor(white: 0.8, alpha: 1), bold: false,
                                lines: zoomFactor >= 1.5 ? 4 : zoomFactor > 1 ? 3 : 1)
            snippet.preferredMaxLayoutWidth = w
            // exact width: the text block always spans the card instead of
            // drifting as Auto Layout re-solves during the zoom animation
            snippet.widthAnchor.constraint(equalToConstant: w).isActive = true
            views.append(snippet)
        }
        let status: (String, NSColor) = s.anyBusy ? (L("st_working"), .systemGreen)
            : s.anyLive ? (L("st_waiting"), .systemOrange)
            : (L("st_done"), NSColor.systemGreen.withAlphaComponent(0.75))
        views.append(label(status.0, size: 10, color: status.1, bold: true))

        let col = NSStackView(views: views)
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 3
        col.translatesAutoresizingMaskIntoConstraints = false
        top.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        let accent = s.kind == .claude ? IndicatorView.claudeOrange : IndicatorView.codexTeal
        card.layer?.borderColor = (s.anyBusy ? accent.withAlphaComponent(0.55)
                                             : NSColor(white: 0.2, alpha: 1)).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            card.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        return card
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool, lines: Int = 1) -> NSTextField {
        let l: NSTextField
        if lines > 1 {
            // a real wrapping label — plain labels truncate to one line no
            // matter what maximumNumberOfLines says
            l = NSTextField(wrappingLabelWithString: text)
            l.isEditable = false
            l.isSelectable = false
            l.maximumNumberOfLines = lines
            l.preferredMaxLayoutWidth = 430 * zoomFactor
        } else {
            l = NSTextField(labelWithString: text)
            l.lineBreakMode = .byTruncatingTail
        }
        l.font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        l.textColor = color
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
enum AgentGlyphState { case inactive, running, idle, done }

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
        case .running: x = drawClaudeRunning(ctx, right: x, cy: cy, dim: false) - 6
        case .idle: x = drawClaudeRunning(ctx, right: x, cy: cy, dim: true) - 6
        case .done: drawGreenBlob(ctx, right: x, cy: cy); x -= 24
        case .inactive: break
        }
        switch codexState {
        case .running: _ = drawCodexPet(ctx, right: x, cy: cy, dim: false)
        case .idle: _ = drawCodexPet(ctx, right: x, cy: cy, dim: true)
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
    private func drawCrab(_ ctx: CGContext, right: CGFloat, cy: CGFloat, dim: Bool) -> CGFloat {
        // terminal cells are ~2x taller than wide — keep that aspect or he squishes
        let subW: CGFloat = 1.6, subH: CGFloat = 3.2
        let walk = dim ? 0 : Int(t * 2.5)
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
                    let alpha = (isFeet ? 1.0 : 0.8 + 0.2 * r) * (dim ? 0.4 : 1.0)
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
            // app bundle: Contents/MacOS/../Resources/pets
            exeDir.appendingPathComponent("../Resources/pets/pet-\(currentPetID).webp")
                .standardizedFileURL.path,
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

    /// Claude slot: custom GIF if configured, else the built-in walking
    /// mascot. `dim` = session alive but quiet: static and faded, so the
    /// indicator never just vanishes mid-session.
    private func drawClaudeRunning(_ ctx: CGContext, right: CGFloat, cy: CGFloat, dim: Bool) -> CGFloat {
        if let gif = Self.claudeGif {
            let h: CGFloat = 26, w = h * gif.aspect
            let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
            gif.draw(in: dest, t: dim ? 0 : t, alpha: dim ? 0.4 : 1)
            return dest.minX
        }
        return drawCrab(ctx, right: right, cy: cy, dim: dim)
    }

    private func drawCodexPet(_ ctx: CGContext, right: CGFloat, cy: CGFloat, dim: Bool) -> CGFloat {
        if let gif = Self.codexGif {
            let h: CGFloat = 26, w = h * gif.aspect
            let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
            gif.draw(in: dest, t: dim ? 0 : t, alpha: dim ? 0.4 : 1)
            return dest.minX
        }
        guard let sprite = Self.codexSprite else {
            return drawRing(ctx, right: right, cy: cy, color: Self.codexTeal, dim: dim)
        }
        let fw: CGFloat = 192, fh: CGFloat = 208
        let idx = dim ? 0 : Int(t / 0.12) % 8
        let src = NSRect(x: CGFloat(idx) * fw, y: 1872 - 2 * fh, width: fw, height: fh)
        let h: CGFloat = 26, w = h * fw / fh
        let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
        NSGraphicsContext.current?.imageInterpolation = .none  // keep the pixel art crisp
        sprite.draw(in: dest, from: src, operation: .sourceOver, fraction: dim ? 0.4 : 1)
        return dest.minX
    }

    /// Returns the left edge of what was drawn.
    private func drawRing(_ ctx: CGContext, right: CGFloat, cy: CGFloat, color: NSColor, dim: Bool = false) -> CGFloat {
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
                let a = intensity * intensity * (0.55 + 0.45 * r) * (dim ? 0.4 : 1)
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

/// Scroll-view document container with top-down coordinates (for the GIF gallery).
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Settings preview: a mini black notch bar showing the CURRENT mascot of an
/// agent at its real size, animated exactly as it renders next to the notch.
final class MascotBarPreview: NSView {
    private let ind = IndicatorView()
    private var timer: Timer?
    private var t: CGFloat = 0

    init(kind: AgentKind) {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 32))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 140).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        ind.frame = NSRect(x: 6, y: 2, width: 128, height: 28)
        ind.autoresizingMask = [.width, .height]
        if kind == .claude { ind.claudeState = .running } else { ind.codexState = .running }
        addSubview(ind)
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.t += 0.12
            self.ind.t = self.t
        }
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        if window == nil { timer?.invalidate(); timer = nil }
    }
}

/// Compact quick-folders pane: a single-column browser to hop between
/// directories fast (double-click navigates, files open, rows drag out).
/// Lives on its own shortcut, separate from the Finder-style pane.
final class QuickFoldersPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var dir: URL
    private var items: [URL] = []
    private let table = NSTableView()
    private let pathLabel = NSTextField(labelWithString: "")
    /// Fired when the USER navigates here — the app `cd`s the terminal to match.
    var onNavigate: ((URL) -> Void)?
    private var hasParent: Bool { dir.path != "/" }
    private func itemIndex(forRow row: Int) -> Int? {
        let idx = row - (hasParent ? 1 : 0)
        return idx >= 0 && idx < items.count ? idx : nil
    }

    /// External sync (terminal `cd`): update the view without echoing back.
    func setDirectory(_ url: URL) {
        guard url.path != dir.path else { return }
        dir = url
        reload()
    }

    init(startDir: URL) {
        dir = startDir
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 300))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // hard minimum: the split view must never crush the pane into a sliver
        widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let up = NSButton(title: "▲", target: self, action: #selector(goUp))
        up.isBordered = false
        up.contentTintColor = .systemGreen
        up.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        table.addTableColumn(NSTableColumn(identifier: .init("file")))
        table.headerView = nil
        table.backgroundColor = .black
        table.rowHeight = 22
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openRow)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(up)
        addSubview(pathLabel)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            up.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            up.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            up.widthAnchor.constraint(equalToConstant: 20),
            pathLabel.centerYAnchor.constraint(equalTo: up.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: up.trailingAnchor, constant: 4),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: up.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        reload()
    }
    required init?(coder: NSCoder) { nil }

    private func reload() {
        items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        items.sort { a, b in
            let ad = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bd = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if ad != bd { return ad && !bd }  // folders first, for hopping around
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
        pathLabel.stringValue = dir.path
        table.reloadData()
    }

    private func navigateAndNotify(_ url: URL) {
        dir = url
        reload()
        onNavigate?(url)
    }

    @objc private func goUp() {
        let parent = dir.deletingLastPathComponent()
        guard parent.path != dir.path else { return }
        navigateAndNotify(parent)
    }

    @objc private func openRow() {
        let row = table.clickedRow
        if hasParent, row == 0 { goUp(); return }  // the ".." row
        guard let idx = itemIndex(forRow: row) else { return }
        let url = items[idx]
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if vals?.isDirectory == true, vals?.isPackage != true {
            navigateAndNotify(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count + (hasParent ? 1 : 0) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if hasParent, row == 0 {
            let parent = dir.deletingLastPathComponent()
            return quickCell(icon: NSWorkspace.shared.icon(forFile: parent.path), text: "..")
        }
        guard let idx = itemIndex(forRow: row) else { return nil }
        let url = items[idx]
        return quickCell(icon: NSWorkspace.shared.icon(forFile: url.path), text: url.lastPathComponent)
    }

    private func quickCell(icon iconImage: NSImage, text: String) -> NSView {
        let cell = NSTableCellView()
        let icon = NSImageView(image: iconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: text)
        name.textColor = NSColor(white: 0.9, alpha: 1)
        name.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(name)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let idx = itemIndex(forRow: row) else { return nil }  // ".." doesn't drag
        return items[idx] as NSURL
    }
}

/// Key handling for the file table: Space = Quick Look, ⌘C copy, ⌘V paste,
/// ⌘↑ go up (Finder muscle memory).
final class FBTableView: NSTableView {
    var onSpace: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onUp: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { onSpace?(); return }
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 126 { onUp?(); return }  // ⌘↑
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": onCopy?(); return
            case "v": onPaste?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}

/// Embedded Finder-style pane (⌘F), fully independent of the terminal panes:
/// sidebar with the standard macOS locations plus your own favorites (drag a
/// folder onto the sidebar to pin it, right-click to unpin), a real file
/// list (name/date/size, multi-select), Quick Look on Space, ⌘C/⌘V,
/// double-click opens files with their default app, and every row drags out
/// as a real file — into the notch terminals or anywhere else in macOS.
/// (Finder's own sidebar favorites have no supported public API, hence the
/// standard-locations + own-favorites approach.)
final class FileBrowserPane: NSView, NSTableViewDataSource, NSTableViewDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var dir: URL
    private var items: [URL] = []
    private var sidebar: [(title: String, url: URL, custom: Bool)] = []
    private var previewItems: [URL] = []
    private let sideTable = NSTableView()
    private let table = FBTableView()
    private let pathLabel = NSTextField(labelWithString: "")

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    init(startDir: URL) {
        dir = startDir
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // hard minimum: sidebar (140) + a usable file list — without this the
        // split can squeeze the pane until only the sidebar remains visible
        widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true

        // sidebar
        sideTable.addTableColumn(NSTableColumn(identifier: .init("side")))
        sideTable.headerView = nil
        sideTable.backgroundColor = NSColor(white: 0.07, alpha: 1)
        sideTable.rowHeight = 24
        sideTable.style = .plain
        sideTable.dataSource = self
        sideTable.delegate = self
        sideTable.registerForDraggedTypes([.fileURL])  // drop a folder to pin it
        let sideMenu = NSMenu()
        let unpin = NSMenuItem(title: L("remove_fav"), action: #selector(removeFavorite), keyEquivalent: "")
        unpin.target = self
        sideMenu.addItem(unpin)
        sideTable.menu = sideMenu
        let sideScroll = NSScrollView()
        sideScroll.documentView = sideTable
        sideScroll.hasVerticalScroller = true
        sideScroll.drawsBackground = true
        sideScroll.backgroundColor = NSColor(white: 0.07, alpha: 1)
        sideScroll.translatesAutoresizingMaskIntoConstraints = false

        // path bar
        let up = NSButton(title: "▲", target: self, action: #selector(goUp))
        up.isBordered = false
        up.contentTintColor = .systemGreen
        up.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // file list
        let cName = NSTableColumn(identifier: .init("name"))
        cName.title = L("col_name")
        cName.width = 190
        let cDate = NSTableColumn(identifier: .init("date"))
        cDate.title = L("col_modified")
        cDate.width = 110
        let cSize = NSTableColumn(identifier: .init("size"))
        cSize.title = L("col_size")
        cSize.width = 64
        table.addTableColumn(cName)
        table.addTableColumn(cDate)
        table.addTableColumn(cSize)
        table.backgroundColor = .black
        table.rowHeight = 22
        table.style = .plain
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openRow)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.onSpace = { [weak self] in self?.toggleQuickLook() }
        table.onCopy = { [weak self] in self?.copySelection() }
        table.onPaste = { [weak self] in self?.pasteIntoDir() }
        table.onUp = { [weak self] in self?.goUp() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(sideScroll)
        addSubview(up)
        addSubview(pathLabel)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            sideScroll.topAnchor.constraint(equalTo: topAnchor),
            sideScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            sideScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            sideScroll.widthAnchor.constraint(equalToConstant: 140),
            up.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            up.leadingAnchor.constraint(equalTo: sideScroll.trailingAnchor, constant: 6),
            up.widthAnchor.constraint(equalToConstant: 20),
            pathLabel.centerYAnchor.constraint(equalTo: up.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: up.trailingAnchor, constant: 4),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: up.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: sideScroll.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        rebuildSidebar()
        reload()
    }
    required init?(coder: NSCoder) { nil }

    // MARK: navigation

    private func navigate(to url: URL) {
        dir = url
        reload()
    }

    @objc private func goUp() {
        let parent = dir.deletingLastPathComponent()
        guard parent.path != dir.path else { return }
        navigate(to: parent)
    }

    @objc private func openRow() {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        let url = items[row]
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if vals?.isDirectory == true, vals?.isPackage != true {
            navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        items = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        // newest first — screenshots and fresh downloads float to the top
        items.sort { a, b in
            let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return ad > bd
        }
        pathLabel.stringValue = dir.path
        table.reloadData()
    }

    // MARK: sidebar / favorites

    private var favoritesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/favorites")
    }

    private func rebuildSidebar() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var entries: [(title: String, url: URL, custom: Bool)] = []
        func add(_ url: URL?, name: String? = nil) {
            guard let url, fm.fileExists(atPath: url.path) else { return }
            entries.append((name ?? fm.displayName(atPath: url.path), url, false))
        }
        add(home)
        add(URL(fileURLWithPath: "/Applications"))
        add(fm.urls(for: .desktopDirectory, in: .userDomainMask).first)
        add(fm.urls(for: .documentDirectory, in: .userDomainMask).first)
        add(fm.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        add(fm.urls(for: .picturesDirectory, in: .userDomainMask).first)
        add(fm.urls(for: .musicDirectory, in: .userDomainMask).first)
        add(fm.urls(for: .moviesDirectory, in: .userDomainMask).first)
        add(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), name: "iCloud Drive")
        let favs: [(title: String, url: URL, custom: Bool)] =
            ((try? String(contentsOf: favoritesURL, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { URL(fileURLWithPath: String($0)) }
                .filter { fm.fileExists(atPath: $0.path) }
                .map { (fm.displayName(atPath: $0.path), $0, true) }
        sidebar = entries + favs
        sideTable.reloadData()
    }

    private func saveFavorites() {
        let paths = sidebar.filter { $0.custom }.map { $0.url.path }.joined(separator: "\n")
        try? paths.write(to: favoritesURL, atomically: true, encoding: .utf8)
    }

    @objc private func removeFavorite() {
        let row = sideTable.clickedRow
        guard row >= 0, row < sidebar.count, sidebar[row].custom else { return }
        sidebar.remove(at: row)
        saveFavorites()
        sideTable.reloadData()
    }

    // MARK: clipboard / Quick Look

    private var selectedURLs: [URL] {
        table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
    }

    private func copySelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    /// ⌘V copies the pasteboard's files INTO the current folder (never
    /// overwrites — appends " 2", " 3"… like Finder).
    private func pasteIntoDir() {
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return }
        let fm = FileManager.default
        for src in urls {
            var dest = dir.appendingPathComponent(src.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = src.deletingPathExtension().lastPathComponent
                let ext = src.pathExtension
                dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            try? fm.copyItem(at: src, to: dest)
        }
        reload()
    }

    private func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            previewItems = selectedURLs
            guard !previewItems.isEmpty else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        // the notch terminal floats at statusBar level — lift Quick Look above it
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItems.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    // MARK: tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sideTable ? sidebar.count : items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sideTable {
            guard row < sidebar.count else { return nil }
            let entry = sidebar[row]
            return iconCell(icon: NSWorkspace.shared.icon(forFile: entry.url.path),
                            text: entry.title, color: NSColor(white: 0.85, alpha: 1))
        }
        guard row < items.count else { return nil }
        let url = items[row]
        switch tableColumn?.identifier.rawValue {
        case "name":
            return iconCell(icon: NSWorkspace.shared.icon(forFile: url.path),
                            text: url.lastPathComponent, color: NSColor(white: 0.9, alpha: 1))
        case "date":
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return textCell(d.map { Self.dateFmt.string(from: $0) } ?? "—")
        case "size":
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let text = vals?.isDirectory == true ? "—"
                : ByteCountFormatter.string(fromByteCount: Int64(vals?.fileSize ?? 0), countStyle: .file)
            return textCell(text)
        default:
            return nil
        }
    }

    private func iconCell(icon: NSImage, text: String, color: NSColor) -> NSView {
        let cell = NSTableCellView()
        let iv = NSImageView(image: icon)
        iv.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: text)
        name.textColor = color
        name.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iv)
        cell.addSubview(name)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 5),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func textCell(_ text: String) -> NSView {
        let cell = NSTableCellView()
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        l.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        l.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            l.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            l.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let t = notification.object as? NSTableView else { return }
        if t === sideTable {
            let row = sideTable.selectedRow
            guard row >= 0, row < sidebar.count else { return }
            navigate(to: sidebar[row].url)
        } else if let panel = QLPreviewPanel.shared(), panel.isVisible {
            previewItems = selectedURLs
            panel.reloadData()
        }
    }

    /// File rows drag out as real file URLs (multi-selection drags them all).
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === table, row < items.count else { return nil }
        return items[row] as NSURL
    }

    /// Drop a folder on the sidebar to pin it as a favorite.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        tableView === sideTable ? .copy : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === sideTable,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        else { return false }
        let fm = FileManager.default
        var added = false
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !sidebar.contains(where: { $0.url.path == url.path }) else { continue }
            sidebar.append((fm.displayName(atPath: url.path), url, true))
            added = true
        }
        if added {
            saveFavorites()
            sideTable.reloadData()
        }
        return added
    }
}

/// Terminal pane that accepts dragged files/folders: their shell-quoted
/// paths are typed into the shell, like every serious terminal does.
final class DropTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        let paths = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        send(txt: paths + " ")
        return true
    }
}

/// Header strip of the notch terminal — visual only. The terminal is part of
/// the notch: it cannot be moved, it only hangs centered under it.
final class TermDragStrip: NSView {
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
    var onQuit: (() -> Void)?
    @objc private func quitTapped() { onQuit?() }
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
        let quit = NSMenuItem(title: L("quit"), action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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
            // subtle dark-gray outline so the panel reads against dark walls
            NSColor(white: 0.24, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
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
    private var petPopupRef: NSPopUpButton?
    private var langPopupRef: NSPopUpButton?
    private var soundDoneRef: NSButton?
    private var soundAttRef: NSButton?
    private var pendZoomField: NSTextField?
    private var zoomPct: CGFloat = 25   // hover-zoom percentage (config "zoom")
    private var hotKeyRef2: EventHotKeyRef?
    // one sound per episode: armed while busy, disarmed once played
    private var claudeDoneArmed = false, claudeAttArmed = false
    private var codexDoneArmed = false, codexAttArmed = false
    // debounce: busy must be quiet several polls before it counts as settled,
    // so CPU flapping around the threshold can't re-fire sounds/glyphs
    private var claudeBusyStable = false, codexBusyStable = false
    private var claudeQuietPolls = 0, codexQuietPolls = 0
    private var asks: [AgentAsk] = []
    // tty per live session path/cwd, harvested from discovery, so a reply
    // reaches the right terminal
    private var ttyByPath: [String: String] = [:]
    private var lastSoundAt = Date.distantPast
    private var termWindow: NSPanel?
    private var termSplit: NSSplitView?
    private var termViews: [LocalProcessTerminalView] = []
    private var fileBrowser: FileBrowserPane?
    private var quickFolders: QuickFoldersPane?
    // in-terminal ⌘-keys (configurable): split / files pane / quick folders
    private var keySplit = "d", keyFiles = "f", keyFolders = "e"
    private var panelHotkeyPopupRef: NSPopUpButton?
    private var splitKeyPopupRef: NSPopUpButton?
    private var filesKeyPopupRef: NSPopUpButton?
    private var foldersKeyPopupRef: NSPopUpButton?
    private var termHotkeyPopupRef: NSPopUpButton?
    private var loginCheckRef: NSButton?
    private var pendTermDir = ""
    private var termDirLabel: NSTextField?
    private var pendTermSizeField: NSTextField?
    private var pendPanelAlphaField: NSTextField?
    private var pendTermAlphaField: NSTextField?
    private var extInjectRef: NSButton?
    private var galleryWindow: NSWindow?
    private var gallerySearchField: NSTextField?
    private var galleryTargetPopup: NSPopUpButton?
    private var galleryStack: NSStackView?
    private var galleryResults: [(code: String, names: String)] = []
    private var gallerySelectedCell: NSView?

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
    private let expandedSize = NSSize(width: 560, height: 260)

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
        // one notch above .statusBar so the panel always beats the terminal
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)  // panel is always black
        window.contentView = notchView
        notchView.wantsLayer = true
        notchView.barHeight = barHeight
        // window-level alpha: the WHOLE panel goes translucent, text included
        window.alphaValue = cfgAlpha("panel-alpha")

        // Indicator window: tiny, always interactive, never steals focus
        indicatorWindow = NSPanel(contentRect: indicatorScreenRect,
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        indicatorWindow.isOpaque = false
        indicatorWindow.backgroundColor = .clear
        indicatorWindow.hasShadow = false
        indicatorWindow.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
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
        notchView.onQuit = { [weak self] in self?.confirmQuit() }
        listController.onSettings = { [weak self] in self?.showSettings() }
        listController.onTerminal = { [weak self] in self?.toggleTerminal() }
        listController.onReply = { [weak self] ask, text in self?.replyToAsk(ask, text: text) }
        listController.onFocusAsk = { [weak self] ask in self?.focusTerminalFor(ask) }

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
        // every hotkey is user-configurable — fixed choices always end up
        // colliding with something (browsers, ChatGPT, fingers)
        registerPanelHotkey()
        registerTermHotkey()
        readTermKeys()

        // in-terminal ⌘-keys: split / files pane / quick folders
        // (local monitor: only our own windows)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let w = self.termWindow, e.window === w,
                  e.modifierFlags.contains(.command) else { return e }
            // no menu bar in an accessory app, so route the edit keys by
            // hand: ⌘C/⌘X copy the terminal's mouse selection, ⌘V pastes
            let term = w.firstResponder as? LocalProcessTerminalView
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "c" where term?.selectionActive == true,
                 "x" where term?.selectionActive == true:
                term?.copy(term)
                return nil
            case "v" where term != nil:
                term?.paste(term)
                return nil
            case self.keySplit: self.addTerminalPane(); return nil
            case self.keyFiles: self.toggleFileBrowser(); return nil
            case self.keyFolders: self.toggleQuickFolders(); return nil
            default: return e
            }
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
            let quit = NSMenuItem(title: L("quit"), action: #selector(self.confirmQuit), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
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
        // global monitors don't see clicks in our own windows — this local
        // monitor closes the panel when a click lands on the terminal,
        // settings or gallery windows
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            if let self, self.expanded, e.window !== self.window {
                self.setExpanded(false)
            }
            return e
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
        listController.contentWidth = panelContentWidth()
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
        let small = topAnchoredScale(0.25, 0.06, b)
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
            var cpuByPath: [String: Double] = [:]
            var cpuByCwd: [String: Double] = [:]
            var ttyMap: [String: String] = [:]  // cwd → tty, for routing replies
            for snap in self.discovery.liveTranscripts() {
                if let cwd = snap.cwd { ttyMap[cwd] = snap.tty }
                if let path = snap.transcriptPath {
                    seen.insert(path)
                    cpuByPath[path] = max(cpuByPath[path] ?? 0, snap.cpu)
                } else if snap.kind == .claude, let cwd = snap.cwd {
                    let encoded = encodeProjectDir(cwd)
                    let i = cwdIndex[encoded, default: 0]
                    cwdIndex[encoded] = i + 1
                    seen.insert("cwd#\(encoded)#\(i)")
                    cpuByCwd[encoded] = max(cpuByCwd[encoded] ?? 0, snap.cpu)
                }
            }
            let pendingAsks = self.loadAsks(ttyByCwd: ttyMap)
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
            let result = self.scanner.scan(live: live, claudeCwdCounts: cwdCounts,
                                           cpuByPath: cpuByPath, cpuByCwd: cpuByCwd)
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
                // chime once when a NEW ask arrives (not every poll it persists)
                let newAsk = pendingAsks.contains { a in !self.asks.contains { $0.sessionID == a.sessionID } }
                self.asks = pendingAsks
                self.listController.asks = pendingAsks
                self.listController.sessions = result
                if newAsk, self.soundAttention { self.playSound("Ping") }
                // busy → mascot; alive-but-quiet → nothing (idle, not done);
                // process exited → done blob (cleared on terminal focus)
                let claudeLive = result.contains { $0.kind == .claude && $0.anyLive }
                let codexLive = result.contains { $0.kind == .codex && $0.anyLive }
                let claudeBusyRaw = result.contains { $0.kind == .claude && $0.anyBusy }
                let codexBusyRaw = result.contains { $0.kind == .codex && $0.anyBusy }
                // debounce raw busy: on immediately, off only after 3 quiet
                // polls (~9 s) — one dip in CPU no longer flips the state
                if claudeBusyRaw { self.claudeBusyStable = true; self.claudeQuietPolls = 0 }
                else if self.claudeBusyStable { self.claudeQuietPolls += 1
                    if self.claudeQuietPolls >= 3 { self.claudeBusyStable = false } }
                if codexBusyRaw { self.codexBusyStable = true; self.codexQuietPolls = 0 }
                else if self.codexBusyStable { self.codexQuietPolls += 1
                    if self.codexQuietPolls >= 3 { self.codexBusyStable = false } }
                let claudeBusy = self.claudeBusyStable
                let codexBusy = self.codexBusyStable
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
                if claudeWaits { self.claudeAttArmed = false }
                if codexWaits { self.codexAttArmed = false }
                self.claudePrevBusy = claudeBusy
                self.codexPrevBusy = codexBusy
                // the green "done" blob also requires an armed episode — a
                // liveness flap without real work no longer conjures it up.
                // alive-but-quiet shows a dimmed static mascot (.idle), so the
                // indicator never just vanishes mid-session.
                self.claudeState = claudeBusy ? .running
                    : claudeLive ? .idle
                    : (claudeGone && self.claudeDoneArmed ? .done : self.claudeState)
                self.codexState = codexBusy ? .running
                    : codexLive ? .idle
                    : (codexGone && self.codexDoneArmed ? .done : self.codexState)
                if claudeGone { self.claudeDoneArmed = false; self.claudeAttArmed = false }
                if codexGone { self.codexDoneArmed = false; self.codexAttArmed = false }
                self.claudeWasLive = claudeLive
                self.codexWasLive = codexLive
                self.render()
            }
        }
    }

    private func tick() {
        frame += 1
        checkHover()
        syncQuickFolders()
        // repaint only while something on screen actually animates — an
        // idle/empty indicator repainting 8×/s is pure wasted CPU
        let animating = claudeState == .running || codexState == .running
            || claudeState == .done || codexState == .done
        if animating || expanded { render() }
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
    /// Width available to the panel's text at the current zoom state.
    private func panelContentWidth() -> CGFloat {
        let z: CGFloat = zoomed ? 1 + zoomPct / 100 : 1.0
        return max(expandedSize.width, notchWidth + sidePad * 2) * z - 40
    }

    private func setZoomed(_ on: Bool) {
        guard expanded, zoomed != on, !animating else { return }
        zoomed = on
        listController.contentWidth = panelContentWidth()
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
        // default size = configurable percentage of the screen (config "term-size")
        let sizePct = CGFloat(min(95, max(20, Double((try? String(contentsOf: configURL("term-size"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 50)))
        let tw = max(480, s.width * sizePct / 100)
        let th = max(280, (s.height - barHeight) * sizePct / 100)
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
        panel.isMovable = false  // the terminal IS part of the notch — it doesn't move
        panel.alphaValue = cfgAlpha("term-alpha")  // whole-window transparency
        // any resize re-centers under the notch, so dragging a corner grows
        // the window symmetrically around it
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            guard let self, let w = self.termWindow else { return }
            let s = self.screen.frame
            var f = w.frame
            let tx = s.midX - f.width / 2
            let ty = s.maxY - self.barHeight - f.height
            if abs(f.origin.x - tx) > 0.5 || abs(f.origin.y - ty) > 0.5 {
                f.origin.x = tx
                f.origin.y = ty
                w.setFrame(f, display: true)
            }
        }
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: tw, height: th)))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 16
        container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.layer?.borderColor = NSColor(white: 0.24, alpha: 1).cgColor
        container.layer?.borderWidth = 1
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
        let term = DropTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        term.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        term.nativeBackgroundColor = .black
        term.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        term.caretColor = NSColor(red: 0.1, green: 0.95, blue: 0.35, alpha: 1)  // matrix green
        term.processDelegate = self
        split.addArrangedSubview(term)
        split.adjustSubviews()
        // minimal prompt (project + git branch + blinking green block cursor)
        // via our own ZDOTDIR; the user's ~/.zshrc is still sourced first
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["ZDOTDIR"] = notchZshDir().path
        let shell = env["SHELL"] ?? "/bin/zsh"
        // start folder (config "term-dir"); root if unset or gone
        var startDir = (try? String(contentsOf: configURL("term-dir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if startDir.isEmpty || !FileManager.default.fileExists(atPath: startDir) { startDir = "/" }
        FileManager.default.changeCurrentDirectoryPath(startDir)
        term.startProcess(executable: shell, args: ["-l"],
                          environment: env.map { "\($0.key)=\($0.value)" })
        termViews.append(term)
        termWindow?.makeFirstResponder(term)
    }

    /// Writes the notch terminal's zsh profile: source the user's zshrc, then
    /// override the prompt with `dir branch ❯` and a blinking block cursor.
    private func notchZshDir() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/zsh")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rc = """
        # Agent Notch Plus terminal profile (regenerated on each terminal open)
        export ZDOTDIR="$HOME"
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
        autoload -Uz vcs_info
        zstyle ':vcs_info:*' enable git
        zstyle ':vcs_info:git:*' formats ' %F{cyan}%b%f'
        setopt PROMPT_SUBST
        PROMPT_EOL_MARK=''  # hide zsh's inverse-% partial-line marker
        # inside a git repo: "project branch ❯" — anywhere else just "❯".
        # (No ${:+} nesting: %F{...} braces inside it break the expansion.)
        _notch_prompt() {
          vcs_info
          if [[ -n "$vcs_info_msg_0_" ]]; then
            PROMPT="%F{green}%1~%f$vcs_info_msg_0_ %F{green}❯%f "
          else
            PROMPT="%F{green}❯%f "
          fi
        }
        precmd() { _notch_prompt; print -Pn '\\e[1 q' }
        # Silent cd driven by the quick-folders pane: the app writes the
        # target to cd-target and sends ESC[24;5~ (a sequence no keyboard
        # produces) — the widget changes directory without typing anything.
        _agent_notch_cd() {
          local t
          t="$(command cat "$HOME/.config/agent-notch/cd-target" 2>/dev/null)"
          [[ -n "$t" && -d "$t" ]] && cd "$t"
          _notch_prompt
          zle reset-prompt
        }
        zle -N _agent_notch_cd
        bindkey '\\e[24;5~' _agent_notch_cd
        RPROMPT=''
        """
        try? rc.write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Focused terminal (or the first one), for pane→terminal syncing.
    private var focusedTerminal: LocalProcessTerminalView? {
        termViews.first { $0.window?.firstResponder === $0 } ?? termViews.first
    }

    /// The quick-folders pane navigated — `cd` the terminal to match,
    /// invisibly: write the target and fire the zle widget's trigger
    /// sequence. Nothing is typed, echoed or left in history.
    private func cdTerminal(to url: URL) {
        guard let term = focusedTerminal else { return }
        writeConfig("cd-target", url.path)
        term.send(txt: "\u{1B}[24;5~")
    }

    /// Terminal → pane: mirror the shell's real cwd (read from the kernel)
    /// so `cd ..`, `cd /` etc. show up in the quick-folders pane, ~1×/s.
    private func syncQuickFolders() {
        guard frame % 8 == 0, let qf = quickFolders,
              let pid = focusedTerminal?.process?.shellPid, pid > 0,
              let cwd = pidCwd(pid) else { return }
        qf.setDirectory(URL(fileURLWithPath: cwd))
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
        // force the first layout pass NOW: AppKit resets the layer's
        // anchorPoint on it, which used to flip the very first curtain
        // animation upside down (it unrolled bottom-up)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        curtain(panel, open: true)
    }

    private func hideTerminal(_ panel: NSWindow) {
        curtain(panel, open: false) { panel.orderOut(nil) }
    }

    /// Curtain animation: unroll down from the notch / roll back up into it.
    private func curtain(_ panel: NSWindow, open: Bool, completion: (() -> Void)? = nil) {
        guard let view = panel.contentView, let layer = view.layer else { completion?(); return }
        let b = view.bounds
        let rolled = topAnchoredScale(1, 0.02, b)
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
        fileBrowser = nil
        quickFolders = nil
        termWindow?.orderOut(nil)
        termWindow = nil
        termSplit = nil
    }

    /// Quick-folders pane (compact single-column browser) on its own ⌘-key.
    @objc fileprivate func toggleQuickFolders() {
        guard let split = termSplit else { return }
        if let qf = quickFolders {
            qf.removeFromSuperview()
            quickFolders = nil
            split.adjustSubviews()
            return
        }
        var startDir = (try? String(contentsOf: configURL("term-dir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if startDir.isEmpty || !FileManager.default.fileExists(atPath: startDir) {
            startDir = FileManager.default.homeDirectoryForCurrentUser.path
        }
        let qf = QuickFoldersPane(startDir: URL(fileURLWithPath: startDir))
        qf.onNavigate = { [weak self] url in self?.cdTerminal(to: url) }
        quickFolders = qf
        split.insertArrangedSubview(qf, at: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.adjustSubviews()
        DispatchQueue.main.async { [weak split] in
            split?.setPosition(230, ofDividerAt: 0)
        }
    }

    /// ⌘F: toggle a mini file-browser pane on the left of the split — browse
    /// and drag files into any terminal pane.
    @objc fileprivate func toggleFileBrowser() {
        guard let split = termSplit else { return }
        if let fb = fileBrowser {
            fb.removeFromSuperview()
            fileBrowser = nil
            split.adjustSubviews()
            return
        }
        var startDir = (try? String(contentsOf: configURL("term-dir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if startDir.isEmpty || !FileManager.default.fileExists(atPath: startDir) {
            startDir = FileManager.default.homeDirectoryForCurrentUser.path
        }
        let fb = FileBrowserPane(startDir: URL(fileURLWithPath: startDir))
        fileBrowser = fb
        split.insertArrangedSubview(fb, at: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)  // keep width; terminals flex
        split.adjustSubviews()
        DispatchQueue.main.async { [weak split] in
            split?.setPosition(420, ofDividerAt: 0)  // sidebar + list need real width
        }
    }

    // MARK: - Settings panel

    @objc fileprivate func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // the notch panel folds away — otherwise it lingers behind the
        // settings window with no mouse route left to dismiss it
        if expanded { hoverOpened = false; setExpanded(false) }
        settingsWindow?.close()  // rebuild fresh so staged values start from disk

        func row(_ title: String, _ views: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            let r = NSStackView(views: [l] + views)
            r.orientation = .horizontal
            r.spacing = 8
            return r
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

        let hotkeyPopup = NSPopUpButton()
        hotkeyPopup.addItems(withTitles: Self.termHotkeyOptions.map(\.label))
        if let idx = Self.termHotkeyOptions.firstIndex(where: { $0.id == currentTermHotkeyID() }) {
            hotkeyPopup.selectItem(at: idx)
        }
        termHotkeyPopupRef = hotkeyPopup

        let panelPopup = NSPopUpButton()
        panelPopup.addItems(withTitles: Self.panelHotkeyOptions.map(\.label))
        if let idx = Self.panelHotkeyOptions.firstIndex(where: { $0.id == currentPanelHotkeyID() }) {
            panelPopup.selectItem(at: idx)
        }
        panelHotkeyPopupRef = panelPopup

        func keyPopup(_ current: String) -> NSPopUpButton {
            let p = NSPopUpButton()
            p.addItems(withTitles: Self.termKeyLetters.map { "⌘\($0)" })
            if let idx = Self.termKeyLetters.firstIndex(where: { $0.lowercased() == current }) {
                p.selectItem(at: idx)
            }
            return p
        }
        let splitPop = keyPopup(keySplit)
        splitKeyPopupRef = splitPop
        let filesPop = keyPopup(keyFiles)
        filesKeyPopupRef = filesPop
        let foldersPop = keyPopup(keyFolders)
        foldersKeyPopupRef = foldersPop

        pendTermDir = (try? String(contentsOf: configURL("term-dir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let curTermSize = (try? String(contentsOf: configURL("term-size"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "50"
        let termSizeField = NSTextField(string: curTermSize)
        termSizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        pendTermSizeField = termSizeField
        let termSizePctLabel = NSTextField(labelWithString: "%")
        termSizePctLabel.textColor = .secondaryLabelColor
        func pctField(_ name: String) -> NSTextField {
            let f = NSTextField(string: String(Int(cfgAlpha(name) * 100)))
            f.widthAnchor.constraint(equalToConstant: 48).isActive = true
            return f
        }
        let panelAlphaField = pctField("panel-alpha")
        pendPanelAlphaField = panelAlphaField
        let termAlphaField = pctField("term-alpha")
        pendTermAlphaField = termAlphaField
        let paPct = NSTextField(labelWithString: "%")
        paPct.textColor = .secondaryLabelColor
        let taPct = NSTextField(labelWithString: "%")
        taPct.textColor = .secondaryLabelColor
        let termDirLbl = NSTextField(labelWithString: pendTermDir.isEmpty ? "/" : pendTermDir)
        termDirLbl.textColor = .secondaryLabelColor
        termDirLbl.lineBreakMode = .byTruncatingMiddle
        termDirLbl.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        termDirLabel = termDirLbl

        let linkBtn = NSButton(title: "github.com/clzidev/agent-notch-plus", target: self,
                               action: #selector(openProjectPage))
        linkBtn.isBordered = false
        linkBtn.contentTintColor = .linkColor
        let versionLbl = NSTextField(labelWithString: "v\(appVersion) · @clzidev")
        versionLbl.textColor = .secondaryLabelColor
        versionLbl.font = .systemFont(ofSize: 11)

        let hookBtn = NSButton(title: hookInstalled() ? L("uninstall_hook") : L("install_hook"),
                               target: self, action: #selector(toggleHook))
        hookBtn.bezelStyle = .rounded
        hookButtonRef = hookBtn
        let extInjectCheck = NSButton(checkboxWithTitle: L("ext_inject"), target: nil, action: nil)
        extInjectCheck.state = FileManager.default.fileExists(atPath: configURL("ext-inject").path) ? .on : .off
        extInjectRef = extInjectCheck

        let loginCheck = NSButton(checkboxWithTitle: L("login_item"), target: nil, action: nil)
        if #available(macOS 13.0, *) {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginCheck.isEnabled = false
        }
        loginCheckRef = loginCheck

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
            row(L("panel_hotkey"), [panelPopup]),
            row(L("term_hotkey"), [hotkeyPopup]),
            row(L("term_keys"), [splitPop, smallLabel(L("key_split")), filesPop, smallLabel(L("key_files")),
                                 foldersPop, smallLabel(L("key_folders"))]),
            row(L("term_dir"), [termDirLbl, button(L("choose_dir"), #selector(chooseTermDir)),
                                button(L("clear_dir"), #selector(clearTermDir))]),
            row(L("term_size"), [termSizeField, termSizePctLabel]),
            row(L("panel_alpha"), [panelAlphaField, paPct]),
            row(L("term_alpha"), [termAlphaField, taPct]),
            row(L("mascots"), [button(L("gif_gallery"), #selector(showGifGallery))]),
            row(L("preview"), [smallLabel("Claude"), MascotBarPreview(kind: .claude),
                               smallLabel("Codex"), MascotBarPreview(kind: .codex)]),
            row(L("replies_title"), [hookBtn]),
            row("", [extInjectCheck]),
            row(L("startup"), [loginCheck]),
            row(L("sounds_title"), [soundCol]),
            row(L("project"), [linkBtn, versionLbl]),
            saveRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("settings_title")
        w.isReleasedWhenClosed = false
        w.contentView = stack
        let fit = stack.fittingSize
        w.setContentSize(NSSize(width: fit.width + 8, height: fit.height))
        // always above the notch panel AND the terminal, on the notch's screen
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        positionOnNotchScreen(w)
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        saveRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
    }

    /// Center a utility window on the screen that owns the notch, not
    /// whatever screen happens to be "main".
    private func positionOnNotchScreen(_ w: NSWindow) {
        let s = screen.frame
        let f = w.frame
        w.setFrameOrigin(NSPoint(x: s.midX - f.width / 2, y: s.midY - f.height / 2))
    }

    @objc private func saveSettings() {
        if let id = petPopupRef?.titleOfSelectedItem { writeConfig("pet", id) }
        writeConfig("lang", langPopupRef?.indexOfSelectedItem == 1 ? "es" : "en")
        writeConfig("sound-done", soundDoneRef?.state == .on ? "1" : "")
        writeConfig("sound-attention", soundAttRef?.state == .on ? "1" : "")
        let pct = Int(min(100, max(0, Double(pendZoomField?.stringValue ?? "") ?? 25)))
        writeConfig("zoom", String(pct))
        if let idx = termHotkeyPopupRef?.indexOfSelectedItem, idx >= 0, idx < Self.termHotkeyOptions.count {
            writeConfig("term-hotkey", Self.termHotkeyOptions[idx].id)
            registerTermHotkey()
        }
        if let idx = panelHotkeyPopupRef?.indexOfSelectedItem, idx >= 0, idx < Self.panelHotkeyOptions.count {
            writeConfig("panel-hotkey", Self.panelHotkeyOptions[idx].id)
            registerPanelHotkey()
        }
        func saveKey(_ popup: NSPopUpButton?, _ name: String) {
            guard let idx = popup?.indexOfSelectedItem, idx >= 0, idx < Self.termKeyLetters.count else { return }
            writeConfig(name, Self.termKeyLetters[idx].lowercased())
        }
        saveKey(splitKeyPopupRef, "key-split")
        saveKey(filesKeyPopupRef, "key-files")
        saveKey(foldersKeyPopupRef, "key-folders")
        readTermKeys()
        writeConfig("term-dir", pendTermDir)
        let tsz = Int(min(95, max(20, Double(pendTermSizeField?.stringValue ?? "") ?? 50)))
        writeConfig("term-size", String(tsz))
        let pa = Int(min(100, max(30, Double(pendPanelAlphaField?.stringValue ?? "") ?? 100)))
        writeConfig("panel-alpha", String(pa))
        let ta = Int(min(100, max(30, Double(pendTermAlphaField?.stringValue ?? "") ?? 100)))
        writeConfig("term-alpha", String(ta))
        window.alphaValue = CGFloat(pa) / 100
        applyTerminalAlpha(CGFloat(ta) / 100)
        writeConfig("ext-inject", extInjectRef?.state == .on ? "1" : "")
        if #available(macOS 13.0, *), let check = loginCheckRef, check.isEnabled {
            if check.state == .on {
                if Bundle.main.bundleIdentifier == nil {
                    alert(L("login_needs_app"), L("login_needs_app_info"))
                } else if SMAppService.mainApp.status != .enabled {
                    try? SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }
        L10n.refresh()
        readSoundPrefs()
        readZoomPref()
        IndicatorView.refreshPetChoice()
        IndicatorView.refreshCustomGifs()
        settingsWindow?.close()
        settingsWindow = nil
    }

    private func smallLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        l.font = .systemFont(ofSize: 11)
        return l
    }

    @objc private func openProjectPage() {
        NSWorkspace.shared.open(URL(string: projectURL)!)
    }

    // MARK: - Claude Code hook (reply detection)

    private var hookScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agent-notch/notch-hook.py")
    }
    private var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private var hookCommand: String { "/usr/bin/python3 \(hookScriptURL.path)" }

    private func hookInstalled() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let json = String(data: data, encoding: .utf8) else { return false }
        return json.contains("notch-hook.py")
    }

    @objc private func toggleHook() {
        hookInstalled() ? uninstallHook() : installHook()
    }

    private func installHook() {
        let fm = FileManager.default
        try? fm.createDirectory(at: asksDir, withIntermediateDirectories: true)
        // hook script: read the hook JSON on stdin, write an ask file keyed by session
        let py = """
        import sys, json, os, time
        try: d = json.load(sys.stdin)
        except Exception: sys.exit(0)
        base = os.path.expanduser('~/.config/agent-notch/asks')
        os.makedirs(base, exist_ok=True)
        sid = str(d.get('session_id', 'session'))
        safe = ''.join(c if c.isalnum() else '_' for c in sid)
        ev = d.get('hook_event_name', '')
        path = os.path.join(base, safe + '.json')
        if ev in ('Stop', 'UserPromptSubmit'):
            try: os.remove(path)
            except OSError: pass
            sys.exit(0)
        out = {'session_id': sid, 'cwd': d.get('cwd', ''),
               'message': d.get('message', 'Necesita tu respuesta'), 'time': time.time()}
        with open(path, 'w') as f: json.dump(out, f)
        """
        try? py.write(to: hookScriptURL, atomically: true, encoding: .utf8)

        // merge into ~/.claude/settings.json under hooks.{Notification,Stop,UserPromptSubmit}
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeSettingsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { root = obj }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["hooks": [["type": "command", "command": hookCommand]]]
        for event in ["Notification", "Stop", "UserPromptSubmit"] {
            var arr = hooks[event] as? [[String: Any]] ?? []
            let already = arr.contains { ($0["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("notch-hook.py") == true } == true }
            if !already { arr.append(entry) }
            hooks[event] = arr
        }
        root["hooks"] = hooks
        try? fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? data.write(to: claudeSettingsURL)
        }
        alert(L("hook_ok"), L("hook_ok_info"))
        refreshHookButton()
    }

    private func uninstallHook() {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else { return }
        for event in ["Notification", "Stop", "UserPromptSubmit"] {
            guard var arr = hooks[event] as? [[String: Any]] else { continue }
            arr.removeAll { ($0["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("notch-hook.py") == true } == true }
            if arr.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = arr }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        if let d = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? d.write(to: claudeSettingsURL)
        }
        alert(L("hook_off"), L("hook_off_info"))
        refreshHookButton()
    }

    private weak var hookButtonRef: NSButton?
    private func refreshHookButton() {
        hookButtonRef?.title = hookInstalled() ? L("uninstall_hook") : L("install_hook")
    }

    @objc private func chooseTermDir() {
        guard let w = settingsWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // as a sheet: the settings window sits above statusBar level, so a
        // free-floating open panel would be buried underneath it
        panel.beginSheetModal(for: w) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.pendTermDir = url.path
            self.termDirLabel?.stringValue = url.path
        }
    }

    @objc private func clearTermDir() {
        pendTermDir = ""
        termDirLabel?.stringValue = "/"
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
            .trimmingCharacters(in: .newlines).trimmingCharacters(in: .whitespaces)
        zoomPct = CGFloat(min(100, max(0, Double(v ?? "") ?? 25)))
    }

    /// Opacity config (30–100%), returned as 0.3–1.0.
    private func cfgAlpha(_ name: String) -> CGFloat {
        let v = (try? String(contentsOf: configURL(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CGFloat(min(100, max(30, Double(v ?? "") ?? 100))) / 100
    }

    /// Window-level alpha: everything in the terminal — background, text,
    /// panes, header — goes translucent together.
    private func applyTerminalAlpha(_ a: CGFloat) {
        termWindow?.alphaValue = a
    }

    // MARK: - Hotkeys (all configurable)

    static let panelHotkeyOptions: [(id: String, label: String, key: UInt32, mods: UInt32)] = [
        ("ctrl_opt_n", "⌃⌥ N", UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey)),
        ("ctrl_opt_p", "⌃⌥ P", UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey)),
        ("ctrl_opt_m", "⌃⌥ M", UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey)),
        ("ctrl_opt_b", "⌃⌥ B", UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey)),
        ("ctrl_opt_j", "⌃⌥ J", UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey)),
    ]

    static let termKeyLetters = ["D", "E", "F", "G", "J", "K", "L", "O", "P", "U"]

    private func currentPanelHotkeyID() -> String {
        (try? String(contentsOf: configURL("panel-hotkey"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.panelHotkeyOptions[0].id
    }

    private func registerPanelHotkey() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk); hotKeyRef = nil }
        let id = currentPanelHotkeyID()
        let opt = Self.panelHotkeyOptions.first { $0.id == id } ?? Self.panelHotkeyOptions[0]
        let panelKeyID = EventHotKeyID(signature: OSType(0x414E_4348), id: 1)  // 'ANCH'
        RegisterEventHotKey(opt.key, opt.mods, panelKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func cfgLetter(_ name: String, _ def: String) -> String {
        let v = (try? String(contentsOf: configURL(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return v.count == 1 ? v : def
    }

    private func readTermKeys() {
        keySplit = cfgLetter("key-split", "d")
        keyFiles = cfgLetter("key-files", "f")
        keyFolders = cfgLetter("key-folders", "e")
    }

    static let termHotkeyOptions: [(id: String, label: String, key: UInt32, mods: UInt32)] = [
        ("ctrl_opt_space", "⌃⌥ Espacio / Space", UInt32(kVK_Space), UInt32(controlKey | optionKey)),
        ("opt_space", "⌥ Espacio / Space", UInt32(kVK_Space), UInt32(optionKey)),
        ("opt_grave", "⌥ ` ", UInt32(kVK_ANSI_Grave), UInt32(optionKey)),
        ("ctrl_opt_t", "⌃⌥ T", UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey)),
        ("ctrl_opt_y", "⌃⌥ Y", UInt32(kVK_ANSI_Y), UInt32(controlKey | optionKey)),
    ]

    private func currentTermHotkeyID() -> String {
        (try? String(contentsOf: configURL("term-hotkey"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.termHotkeyOptions[0].id
    }

    private func registerTermHotkey() {
        if let hk = hotKeyRef2 { UnregisterEventHotKey(hk); hotKeyRef2 = nil }
        let id = currentTermHotkeyID()
        let opt = Self.termHotkeyOptions.first { $0.id == id } ?? Self.termHotkeyOptions[0]
        let termKeyID = EventHotKeyID(signature: OSType(0x414E_4348), id: 2)
        RegisterEventHotKey(opt.key, opt.mods, termKeyID, GetApplicationEventTarget(), 0, &hotKeyRef2)
    }



    // MARK: - Agent asks (hook-driven) + replies

    private var asksDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agent-notch/asks")
    }

    /// Read pending ask files; attach each session's tty (by cwd) for replies.
    /// Stale asks (>10 min) are swept so a crashed session doesn't linger.
    private func loadAsks(ttyByCwd: [String: String]) -> [AgentAsk] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: asksDir, includingPropertiesForKeys: nil) else { return [] }
        var out: [AgentAsk] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let cwd = (o["cwd"] as? String) ?? ""
            let ts = (o["time"] as? Double) ?? 0
            let when = ts > 0 ? Date(timeIntervalSince1970: ts) : ((try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date())
            if Date().timeIntervalSince(when) > 600 { try? fm.removeItem(at: f); continue }
            out.append(AgentAsk(sessionID: (o["session_id"] as? String) ?? f.lastPathComponent,
                                message: (o["message"] as? String) ?? L("asking"),
                                cwd: cwd, tty: ttyByCwd[cwd] ?? "", time: when))
        }
        return out.sorted { $0.time > $1.time }
    }

    /// Reply to an agent's question. The notch's own terminal is written to
    /// directly (safe, exact). External terminals fall back to Accessibility
    /// keystroke injection into the frontmost app (opt-in) — there is no safe
    /// targeted path since macOS blocks TIOCSTI.
    private func replyToAsk(_ ask: AgentAsk, text: String) {
        clearAsk(ask)
        // 1) notch terminal pane whose shell cwd matches → direct + exact
        if let term = termViews.first(where: { ($0.process?.shellPid).flatMap(pidCwd) == ask.cwd }) ?? focusedTerminal,
           termWindow?.isVisible == true, !ask.cwd.isEmpty,
           termViews.contains(where: { ($0.process?.shellPid).flatMap(pidCwd) == ask.cwd }) {
            term.send(txt: text + "\r")
            return
        }
        // 2) external terminal → Accessibility keystroke injection (opt-in)
        guard FileManager.default.fileExists(atPath: configURL("ext-inject").path) else {
            alert(L("ext_inject"), L("ext_inject_info"))
            return
        }
        injectKeystrokes(text + "\r")
    }

    private func clearAsk(_ ask: AgentAsk) {
        asks.removeAll { $0.sessionID == ask.sessionID }
        listController.asks = asks
        let safe = ask.sessionID.replacingOccurrences(of: "/", with: "_")
        try? FileManager.default.removeItem(at: asksDir.appendingPathComponent("\(safe).json"))
    }

    /// Post a string as keystrokes to the frontmost app (Accessibility).
    private func injectKeystrokes(_ s: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in s.unicodeScalars {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                var u = UniChar(ch.value <= 0xFFFF ? ch.value : 0x0020)
                if ch == "\r" || ch == "\n" {
                    // send Return as the real key so the shell/TUI accepts it
                    let ret = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: down)
                    ret?.post(tap: .cghidEventTap)
                    continue
                }
                e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    private func focusTerminalFor(_ ask: AgentAsk) {
        // notch terminal: just show it. external: nothing reliable to focus,
        // so surface the cwd so the user knows which window to click.
        if termWindow != nil { toggleTerminal(); return }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func confirmQuit() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("quit_confirm")
        a.informativeText = L("quit_confirm_info")
        a.addButton(withTitle: L("quit"))
        a.addButton(withTitle: L("cancel"))
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }

    private func alert(_ msg: String, _ info: String) {
        let a = NSAlert()
        a.messageText = msg
        a.informativeText = info
        a.runModal()
    }

    // MARK: - Animated emoji mascots (Noto Animated Emoji — keyless CDN)
    // Small animated icons with transparent background served by Google at
    // fonts.gstatic.com — no API key, no account. The ONLY network access in
    // the app, used only from the gallery. Names mix EN+ES for local search.

    static let emojiCatalog: [(code: String, names: String)] = [
        ("1f600", "grinning sonrisa feliz happy"),
        ("1f603", "smiley open mouth sonrisa abierta"),
        ("1f604", "smile eyes sonrisa ojos"),
        ("1f601", "beaming grin dientes"),
        ("1f606", "laughing risa"),
        ("1f923", "rofl rodando risa piso"),
        ("1f602", "joy tears lagrimas risa llorar"),
        ("1f609", "wink guiño"),
        ("1f60a", "blush sonrojado tierno"),
        ("1f607", "halo angel santo"),
        ("1f970", "hearts enamorado corazones amor love"),
        ("1f60d", "heart eyes ojos corazon amor love"),
        ("1f929", "star struck estrellas wow"),
        ("1f618", "kiss beso"),
        ("1f60b", "yum rico delicioso"),
        ("1f92a", "zany loco crazy"),
        ("1f914", "thinking pensando"),
        ("1f910", "zipper callado boca cerrada"),
        ("1f634", "sleeping durmiendo zzz"),
        ("1f637", "mask barbijo mascarilla"),
        ("1f975", "hot calor sudor"),
        ("1f976", "cold frio congelado"),
        ("1f92f", "exploding head cabeza explota mind blown"),
        ("1f60e", "sunglasses cool lentes anteojos sol"),
        ("1f913", "nerd geek anteojos"),
        ("1f622", "cry triste lagrima"),
        ("1f62d", "crying llorando fuerte"),
        ("1f620", "angry enojado"),
        ("1f92c", "cursing furioso insultos"),
        ("1f480", "skull calavera muerto"),
        ("1f4a9", "poop caca"),
        ("1f921", "clown payaso"),
        ("1f47b", "ghost fantasma"),
        ("1f47d", "alien extraterrestre ovni"),
        ("1f916", "robot bot"),
        ("1f525", "fire fuego llama"),
        ("1f31f", "glowing star estrella brillante"),
        ("2728", "sparkles destellos brillos"),
        ("1f496", "sparkling heart corazon brillante"),
        ("1f680", "rocket cohete"),
        ("1f389", "party fiesta confeti"),
        ("1f973", "partying face fiesta gorro"),
        ("1f4af", "hundred 100 cien"),
        ("1f440", "eyes ojos mirando"),
        ("1f44b", "wave hola saludo mano"),
        ("1f44d", "thumbs up pulgar like ok"),
        ("1f44f", "clap aplausos"),
        ("1f4aa", "muscle musculo fuerza"),
        ("1f60f", "smirk picaro"),
        ("1f644", "rolling eyes ojos en blanco"),
        ("1f643", "upside down dado vuelta"),
        ("1f911", "money dinero plata"),
        ("1f61b", "tongue lengua"),
        ("1f624", "steam resoplando bufando"),
        ("1f631", "scream grito miedo"),
        ("1f628", "fearful asustado"),
        ("1f979", "holding tears aguantando lagrimas"),
        ("1f60c", "relieved aliviado"),
        ("1f9d0", "monocle inspeccionando detective"),
        ("1f615", "confused confundido"),
    ]

    private static func emojiURL(_ code: String) -> URL {
        URL(string: "https://fonts.gstatic.com/s/e/notoemoji/latest/\(code)/512.gif")!
    }

    private static var emojiPreviewCache: [String: NSImage] = [:]

    // MARK: - Emoji gallery (scrollable feed)

    @objc private func showGifGallery() {
        NSApp.activate(ignoringOtherApps: true)
        if expanded { hoverOpened = false; setExpanded(false) }
        galleryWindow?.close()
        let search = NSTextField(string: "")
        search.placeholderString = "fire, robot, corazón…"
        search.widthAnchor.constraint(equalToConstant: 170).isActive = true
        search.target = self
        search.action = #selector(gallerySearch)
        gallerySearchField = search
        let target = NSPopUpButton()
        target.addItems(withTitles: ["Claude", "Codex"])
        galleryTargetPopup = target
        let top = NSStackView(views: [search, button(L("search"), #selector(gallerySearch)),
                                      NSTextField(labelWithString: L("gif_for")), target,
                                      button(L("restore_default"), #selector(restoreDefaultMascot))])
        top.orientation = .horizontal
        top.spacing = 8
        let hint = NSTextField(labelWithString: L("gallery_hint"))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        galleryStack = grid
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(grid)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: doc.topAnchor),
            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 8 * 64 + 7 * 8 + 16),
            scroll.heightAnchor.constraint(equalToConstant: 380),
        ])

        let previewRow = NSStackView(views: [smallLabel("Claude"), MascotBarPreview(kind: .claude),
                                             smallLabel("Codex"), MascotBarPreview(kind: .codex)])
        previewRow.orientation = .horizontal
        previewRow.spacing = 8

        let root = NSStackView(views: [top, hint, previewRow, scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("gallery_title")
        w.isReleasedWhenClosed = false
        w.contentView = root
        w.setContentSize(root.fittingSize)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        positionOnNotchScreen(w)
        galleryWindow = w
        w.makeKeyAndOrderFront(nil)
        populateGallery(filter: "")
    }

    @objc private func gallerySearch() { populateGallery(filter: gallerySearchField?.stringValue ?? "") }

    /// Local filtering over the curated catalog — no API, no network for the
    /// list itself; only the previews are fetched (and cached) from the CDN.
    private func populateGallery(filter: String) {
        guard let grid = galleryStack else { return }
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = f.isEmpty ? Self.emojiCatalog : Self.emojiCatalog.filter { $0.names.contains(f) }
        galleryResults = matched
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !matched.isEmpty else {
            grid.addArrangedSubview(NSTextField(labelWithString: L("no_results")))
            return
        }
        let perRow = 8
        var i = 0
        while i < matched.count {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            for j in i..<min(i + perRow, matched.count) {
                // animated image view + a transparent button on top: NSButton
                // clicks are rock-solid, NSImageView keeps the animation
                let cell = NSView()
                cell.wantsLayer = true
                cell.layer?.cornerRadius = 8
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.widthAnchor.constraint(equalToConstant: 64).isActive = true
                cell.heightAnchor.constraint(equalToConstant: 64).isActive = true
                let iv = NSImageView()
                iv.animates = true
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(iv)
                let btn = NSButton(title: "", target: self, action: #selector(galleryClicked(_:)))
                btn.isTransparent = true
                btn.tag = j
                btn.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(btn)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: cell.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    btn.topAnchor.constraint(equalTo: cell.topAnchor),
                    btn.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                    btn.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    btn.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                ])
                rowStack.addArrangedSubview(cell)
                let code = matched[j].code
                if let img = Self.emojiPreviewCache[code] {
                    iv.image = img
                } else {
                    URLSession.shared.dataTask(with: Self.emojiURL(code)) { d, _, _ in
                        guard let d, let img = NSImage(data: d) else { return }
                        DispatchQueue.main.async {
                            Self.emojiPreviewCache[code] = img
                            iv.image = img
                        }
                    }.resume()
                }
            }
            grid.addArrangedSubview(rowStack)
            i += perRow
        }
    }

    /// Click: download the emoji GIF, set it as the mascot right away and
    /// outline the chosen cell in green as confirmation.
    @objc private func galleryClicked(_ sender: NSButton) {
        guard sender.tag < galleryResults.count else { return }
        let code = galleryResults[sender.tag].code
        let claude = galleryTargetPopup?.indexOfSelectedItem != 1
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-notch/gifs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("noto-\(code).gif")
        URLSession.shared.dataTask(with: Self.emojiURL(code)) { [weak self] d, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let d, (try? d.write(to: dest)) != nil, GifAnimation(path: dest.path) != nil else {
                    self.alert(L("gif_dl_fail"), "")
                    return
                }
                self.writeConfig(claude ? "claude-gif" : "codex-gif", dest.path)
                IndicatorView.refreshCustomGifs()
                self.gallerySelectedCell?.layer?.borderWidth = 0
                if let cell = sender.superview {
                    cell.layer?.borderColor = NSColor.systemGreen.cgColor
                    cell.layer?.borderWidth = 2
                    self.gallerySelectedCell = cell
                }
            }
        }.resume()
    }

    /// Back to the built-in walking mascot / Codex pet for the chosen agent.
    @objc private func restoreDefaultMascot() {
        let claude = galleryTargetPopup?.indexOfSelectedItem != 1
        writeConfig(claude ? "claude-gif" : "codex-gif", "")
        IndicatorView.refreshCustomGifs()
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
            if self.termViews.isEmpty {
                self.forceCloseTerminal()
            } else {
                // keep typing without clicking: focus the next surviving pane
                self.termWindow?.makeFirstResponder(self.termViews.first)
            }
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
    var cpuByPath: [String: Double] = [:]
    var cpuByCwd: [String: Double] = [:]
    for s in snaps {
        if let p = s.transcriptPath { live.insert(p); cpuByPath[p] = s.cpu }
        else if s.kind == .claude, let c = s.cwd {
            let e = encodeProjectDir(c)
            cwdCounts[e, default: 0] += 1
            cpuByCwd[e] = max(cpuByCwd[e] ?? 0, s.cpu)
        }
    }
    print("== sessions ==")
    for s in SessionScanner().scan(live: live, claudeCwdCounts: cwdCounts, cpuByPath: cpuByPath, cpuByCwd: cpuByCwd) {
        print("\(s.kind.rawValue) [\(s.title)] live=\(s.isLive) busy=\(s.isBusy) cpu=\(s.cpu) mtime=\(-s.lastModified.timeIntervalSinceNow)s kids=\(s.children.count)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
