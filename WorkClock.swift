import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let stateFile = NSString(string: "~/.workclock_state").expandingTildeInPath
    let historyFile = NSString(string: "~/.workclock_history").expandingTildeInPath
    var accumulated: TimeInterval = 0
    var lastTick: Date = Date()
    var paused = false
    let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        loadState()
        lastTick = Date()
        updateDisplay()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, !self.paused else { return }
            let now = Date()
            self.accumulated += now.timeIntervalSince(self.lastTick)
            self.lastTick = now
            self.updateDisplay()
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "History", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(resetTimer), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func loadState() {
        let today = Calendar.current.startOfDay(for: Date())
        guard FileManager.default.fileExists(atPath: stateFile),
              let content = try? String(contentsOfFile: stateFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            accumulated = 0
            saveState()
            return
        }
        let parts = content.split(separator: "\n")
        guard parts.count == 2,
              let datestamp = Double(parts[0]),
              let saved = Double(parts[1]) else {
            accumulated = 0
            saveState()
            return
        }
        let stateDate = Date(timeIntervalSince1970: datestamp)
        if !Calendar.current.isDate(stateDate, inSameDayAs: today) {
            if saved > 0 {
                appendHistory(date: stateDate, seconds: saved)
            }
            accumulated = 0
            saveState()
            return
        }
        accumulated = saved
    }

    func saveState() {
        let content = "\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)\n\(accumulated)"
        try? content.write(toFile: stateFile, atomically: true, encoding: .utf8)
    }

    @objc func screenLocked() {
        pause()
    }

    @objc func willSleep() {
        pause()
    }

    @objc func screenUnlocked() {
        resume()
    }

    @objc func didWake() {
        resume()
    }

    func pause() {
        guard !paused else { return }
        let now = Date()
        accumulated += now.timeIntervalSince(lastTick)
        paused = true
        saveState()
        updateDisplay()
    }

    func resume() {
        loadState()
        lastTick = Date()
        paused = false
        updateDisplay()
    }

    func updateDisplay() {
        let elapsed = Int(accumulated)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        let text = String(format: "⏱ %02d:%02d:%02d", hours, minutes, seconds)

        let color: NSColor
        if hours >= 10 {
            color = .systemRed
        } else if hours >= 8 {
            color = .systemOrange
        } else {
            color = .labelColor
        }

        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color]
        )
    }

    func appendHistory(date: Date, seconds: Double) {
        let elapsed = Int(seconds)
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        let line = String(format: "%@  %02d:%02d:%02d\n", dateFmt.string(from: date), h, m, s)
        if let handle = FileHandle(forWritingAtPath: historyFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: historyFile, atomically: true, encoding: .utf8)
        }
    }

    func loadHistory() -> [String] {
        guard let content = try? String(contentsOfFile: historyFile, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").map(String.init).suffix(14).reversed()
    }

    @objc func resetTimer() {
        accumulated = 0
        lastTick = Date()
        paused = false
        saveState()
        updateDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !paused {
            accumulated += Date().timeIntervalSince(lastTick)
        }
        saveState()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let historyItem = menu.items.first(where: { $0.title == "History" }) else { return }
        let sub = NSMenu()
        let history = loadHistory()
        if history.isEmpty {
            sub.addItem(NSMenuItem(title: "No history yet", action: nil, keyEquivalent: ""))
        } else {
            for entry in history {
                sub.addItem(NSMenuItem(title: entry, action: nil, keyEquivalent: ""))
            }
        }
        historyItem.submenu = sub
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
