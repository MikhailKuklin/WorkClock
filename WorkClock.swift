import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let stateFile = NSString(string: "~/.workclock_state").expandingTildeInPath
    let historyFile = NSString(string: "~/.workclock_history").expandingTildeInPath
    var accumulated: TimeInterval = 0
    var lastTick: Date = Date()
    var currentDay: Date = Calendar.current.startOfDay(for: Date())
    var paused = false
    var manuallyPaused = false
    var pauseMenuItem: NSMenuItem!
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
            let today = Calendar.current.startOfDay(for: now)
            if today != self.currentDay {
                // Day changed — archive yesterday and reset
                self.accumulated += now.timeIntervalSince(self.lastTick)
                if self.accumulated > 0 {
                    self.appendHistory(date: self.currentDay, seconds: self.accumulated)
                }
                self.accumulated = 0
                self.currentDay = today
                self.lastTick = now
                self.saveState()
                self.updateDisplay()
                return
            }
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
        pauseMenuItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Adjust Time…", action: #selector(adjustTime), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "History", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Weekly Stats", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Global Stats", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(resetTimer), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func loadState() {
        let today = Calendar.current.startOfDay(for: Date())
        // Always track the current day. The timer's midnight rollover archives
        // under `currentDay`, so leaving it stale here (e.g. on the cross-day
        // wake path below) makes a later rollover stamp time under the wrong
        // date — which the appendHistory dedup can then silently drop.
        currentDay = today
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
        if !manuallyPaused { resume() }
    }

    @objc func didWake() {
        if !manuallyPaused { resume() }
    }

    @objc func togglePause() {
        if manuallyPaused {
            manuallyPaused = false
            resume()
        } else {
            manuallyPaused = true
            pause()
        }
    }

    func pause() {
        guard !paused else { return }
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        if lastTick < todayStart {
            // lastTick was yesterday — split time at midnight
            let secondsBeforeMidnight = todayStart.timeIntervalSince(lastTick)
            let previousDayTotal = accumulated + secondsBeforeMidnight
            if previousDayTotal > 0 {
                appendHistory(date: lastTick, seconds: previousDayTotal)
            }
            accumulated = now.timeIntervalSince(todayStart)
            currentDay = todayStart
        } else {
            accumulated += now.timeIntervalSince(lastTick)
        }

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
        let icon = manuallyPaused ? "⏸" : "⏱"
        let text = String(format: "%@ %02d:%02d:%02d", icon, hours, minutes, seconds)

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
        pauseMenuItem?.title = manuallyPaused ? "Resume" : "Pause"
    }

    func appendHistory(date: Date, seconds: Double) {
        let dateStr = dateFmt.string(from: date)
        let elapsed = Int(seconds)
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        let newTime = String(format: "%02d:%02d:%02d", h, m, s)

        // Read existing entries
        var lines: [String] = []
        if let content = try? String(contentsOfFile: historyFile, encoding: .utf8) {
            lines = content.split(separator: "\n").map(String.init)
        }

        // Check if date already exists — keep the larger value
        if let idx = lines.firstIndex(where: { $0.hasPrefix(dateStr) }) {
            let parts = lines[idx].split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let tp = parts[1].split(separator: ":").compactMap { Int($0) }
                let existingSecs = (tp.count == 3) ? tp[0] * 3600 + tp[1] * 60 + tp[2] : 0
                if elapsed <= existingSecs { return }
            }
            lines[idx] = "\(dateStr)  \(newTime)"
        } else {
            lines.append("\(dateStr)  \(newTime)")
        }

        let content = lines.map { $0 + "\n" }.joined()
        try? content.write(toFile: historyFile, atomically: true, encoding: .utf8)
    }

    func loadHistory() -> [String] {
        guard let content = try? String(contentsOfFile: historyFile, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").map(String.init).suffix(14).reversed()
    }

    func loadHistoryEntries() -> [(date: String, time: String)] {
        guard let content = try? String(contentsOfFile: historyFile, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            return (date: parts[0], time: parts[1])
        }
    }

    func updateHistoryEntry(dateStr: String, newSeconds: Int) {
        var entries = loadHistoryEntries()
        if let idx = entries.firstIndex(where: { $0.date == dateStr }) {
            let h = newSeconds / 3600
            let m = (newSeconds % 3600) / 60
            let s = newSeconds % 60
            entries[idx] = (date: dateStr, time: String(format: "%02d:%02d:%02d", h, m, s))
        }
        let content = entries.map { "\($0.date)  \($0.time)\n" }.joined()
        try? content.write(toFile: historyFile, atomically: true, encoding: .utf8)
    }

    func addHistoryEntry(dateStr: String, seconds: Int) {
        var entries = loadHistoryEntries()
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        let timeStr = String(format: "%02d:%02d:%02d", h, m, s)
        // Insert in sorted position
        if let idx = entries.firstIndex(where: { $0.date > dateStr }) {
            entries.insert((date: dateStr, time: timeStr), at: idx)
        } else {
            entries.append((date: dateStr, time: timeStr))
        }
        let content = entries.map { "\($0.date)  \($0.time)\n" }.joined()
        try? content.write(toFile: historyFile, atomically: true, encoding: .utf8)
    }

    @objc func adjustHistoryEntry(_ sender: NSMenuItem) {
        guard let dateStr = sender.representedObject as? String else { return }

        let entries = loadHistoryEntries()
        let existing = entries.first(where: { $0.date == dateStr })
        let timeParts = existing?.time.split(separator: ":").compactMap { Int($0) } ?? [0, 0, 0]
        let currentH = timeParts.count >= 1 ? timeParts[0] : 0
        let currentM = timeParts.count >= 2 ? timeParts[1] : 0

        let alert = NSAlert()
        alert.messageText = "Adjust Time for \(dateStr)"
        alert.informativeText = "Current: \(String(format: "%02d:%02d", currentH, currentM))\nEnter new time as HH:MM (e.g. 07:30):"
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(format: "%02d:%02d", currentH, currentM)
        input.alignment = .center
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let text = input.stringValue.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), h >= 0,
              let m = Int(parts[1]), m >= 0, m < 60 else {
            let err = NSAlert()
            err.messageText = "Invalid format"
            err.informativeText = "Please use HH:MM (e.g. 07:30)"
            err.runModal()
            return
        }

        let newSeconds = h * 3600 + m * 60
        if existing != nil {
            updateHistoryEntry(dateStr: dateStr, newSeconds: newSeconds)
        } else {
            addHistoryEntry(dateStr: dateStr, seconds: newSeconds)
        }
    }

    @objc func adjustTime() {
        let wasPaused = paused
        if !wasPaused {
            let now = Date()
            accumulated += now.timeIntervalSince(lastTick)
            lastTick = now
        }

        let currentH = Int(accumulated) / 3600
        let currentM = (Int(accumulated) % 3600) / 60

        let alert = NSAlert()
        alert.messageText = "Adjust Tracked Time"
        alert.informativeText = "Current: \(String(format: "%02d:%02d", currentH, currentM))\nEnter new time as HH:MM (e.g. 07:30):"
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(format: "%02d:%02d", currentH, currentM)
        input.alignment = .center
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let text = input.stringValue.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), h >= 0,
              let m = Int(parts[1]), m >= 0, m < 60 else {
            let err = NSAlert()
            err.messageText = "Invalid format"
            err.informativeText = "Please use HH:MM (e.g. 07:30)"
            err.runModal()
            return
        }

        accumulated = TimeInterval(h * 3600 + m * 60)
        lastTick = Date()
        saveState()
        updateDisplay()
    }

    @objc func addPastDay() {
        let alert = NSAlert()
        alert.messageText = "Add Past Day"
        alert.informativeText = "Enter date and time as YYYY-MM-DD HH:MM\n(e.g. 2026-03-10 08:15):"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        input.stringValue = "\(dateFmt.string(from: yesterday)) 07:30"
        input.alignment = .center
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let text = input.stringValue.trimmingCharacters(in: .whitespaces)
        let textParts = text.split(separator: " ")
        guard textParts.count == 2 else {
            showFormatError("Please use YYYY-MM-DD HH:MM (e.g. 2026-03-10 08:15)")
            return
        }
        let dateStr = String(textParts[0])
        guard dateFmt.date(from: dateStr) != nil else {
            showFormatError("Invalid date. Please use YYYY-MM-DD format.")
            return
        }
        // Don't allow adding for today
        if dateStr == dateFmt.string(from: Date()) {
            showFormatError("Use 'Adjust Time…' to change today's time.")
            return
        }
        let timeParts = textParts[1].split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 2, timeParts[0] >= 0, timeParts[1] >= 0, timeParts[1] < 60 else {
            showFormatError("Invalid time. Please use HH:MM format.")
            return
        }
        // Check if entry already exists
        let entries = loadHistoryEntries()
        if entries.contains(where: { $0.date == dateStr }) {
            updateHistoryEntry(dateStr: dateStr, newSeconds: timeParts[0] * 3600 + timeParts[1] * 60)
        } else {
            addHistoryEntry(dateStr: dateStr, seconds: timeParts[0] * 3600 + timeParts[1] * 60)
        }
    }

    func showFormatError(_ message: String) {
        let err = NSAlert()
        err.messageText = "Invalid format"
        err.informativeText = message
        err.runModal()
    }

    @objc func resetTimer() {
        accumulated = 0
        lastTick = Date()
        paused = false
        manuallyPaused = false
        saveState()
        updateDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !paused {
            let now = Date()
            let todayStart = Calendar.current.startOfDay(for: now)
            if lastTick < todayStart {
                let secondsBeforeMidnight = todayStart.timeIntervalSince(lastTick)
                let previousDayTotal = accumulated + secondsBeforeMidnight
                if previousDayTotal > 0 {
                    appendHistory(date: lastTick, seconds: previousDayTotal)
                }
                accumulated = now.timeIntervalSince(todayStart)
                currentDay = todayStart
            } else {
                accumulated += now.timeIntervalSince(lastTick)
            }
        }
        saveState()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // History submenu
        if let historyItem = menu.items.first(where: { $0.title == "History" }) {
            let sub = NSMenu()
            let entries = loadHistoryEntries().suffix(14).reversed()
            if entries.isEmpty {
                sub.addItem(NSMenuItem(title: "No history yet", action: nil, keyEquivalent: ""))
            } else {
                for entry in entries {
                    let item = NSMenuItem(title: "\(entry.date)  \(entry.time)", action: #selector(adjustHistoryEntry(_:)), keyEquivalent: "")
                    item.representedObject = entry.date
                    item.toolTip = "Click to adjust"
                    sub.addItem(item)
                }
            }
            sub.addItem(NSMenuItem.separator())
            sub.addItem(NSMenuItem(title: "Add Past Day…", action: #selector(addPastDay), keyEquivalent: ""))
            historyItem.submenu = sub
        }

        // Weekly stats submenu
        if let statsItem = menu.items.first(where: { $0.title == "Weekly Stats" }) {
            statsItem.submenu = buildWeeklyStatsMenu()
        }

        // Global stats submenu
        if let globalItem = menu.items.first(where: { $0.title == "Global Stats" }) {
            globalItem.submenu = buildGlobalStatsMenu()
        }
    }

    private var workdayThreshold: Double { 7.5 * 3600 } // 7h 30m

    // High-contrast balance colors that adapt to the menu appearance:
    // vivid on dark/vibrant menus, deep and saturated on light menus.
    private func balanceColor(positive: Bool) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if positive {
                return isDark
                    ? NSColor(srgbRed: 0.32, green: 0.92, blue: 0.46, alpha: 1) // bright green
                    : NSColor(srgbRed: 0.00, green: 0.60, blue: 0.24, alpha: 1) // deep green
            } else {
                return isDark
                    ? NSColor(srgbRed: 1.00, green: 0.45, blue: 0.42, alpha: 1) // coral red
                    : NSColor(srgbRed: 0.82, green: 0.06, blue: 0.10, alpha: 1) // deep red
            }
        }
    }

    // Gather all history entries + today's running total.
    private func gatherDayData() -> [(date: Date, seconds: Double)] {
        var dayData: [(date: Date, seconds: Double)] = []
        if let content = try? String(contentsOfFile: historyFile, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2,
                      let date = dateFmt.date(from: parts[0]) else { continue }
                let timeParts = parts[1].split(separator: ":").compactMap { Int($0) }
                guard timeParts.count == 3 else { continue }
                let secs = Double(timeParts[0] * 3600 + timeParts[1] * 60 + timeParts[2])
                dayData.append((date: date, seconds: secs))
            }
        }
        // Add today
        let todaySecs = paused ? accumulated : accumulated + Date().timeIntervalSince(lastTick)
        dayData.append((date: Date(), seconds: todaySecs))
        return dayData
    }

    // Cumulative balance vs the workday threshold (weekends count fully as extra).
    private func balanceSeconds(for entries: [(date: Date, seconds: Double)]) -> Double {
        let cal = Calendar.current
        var extraSeconds: Double = 0
        for entry in entries {
            let weekday = cal.component(.weekday, from: entry.date) // 1=Sun, 7=Sat
            let isWeekend = weekday == 1 || weekday == 7
            extraSeconds += isWeekend ? entry.seconds : entry.seconds - workdayThreshold
        }
        return extraSeconds
    }

    private func buildGlobalStatsMenu() -> NSMenu {
        let sub = NSMenu()
        let dayData = gatherDayData()

        if dayData.isEmpty {
            sub.addItem(NSMenuItem(title: "No data yet", action: nil, keyEquivalent: ""))
            return sub
        }

        let totalSeconds = dayData.reduce(0.0) { $0 + $1.seconds }
        let extraSeconds = balanceSeconds(for: dayData)

        let header = NSMenuItem(title: "All Time", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "All Time",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        sub.addItem(header)

        let totalH = Int(totalSeconds) / 3600
        let totalM = (Int(totalSeconds) % 3600) / 60
        sub.addItem(NSMenuItem(title: "  Total: \(String(format: "%d:%02d", totalH, totalM))", action: nil, keyEquivalent: ""))

        let absExtra = abs(Int(extraSeconds))
        let extraH = absExtra / 3600
        let extraM = (absExtra % 3600) / 60
        let sign = extraSeconds >= 0 ? "+" : "-"
        let extraStr = "  Balance: \(sign)\(String(format: "%d:%02d", extraH, extraM))"
        let extraItem = NSMenuItem(title: extraStr, action: nil, keyEquivalent: "")
        extraItem.attributedTitle = NSAttributedString(
            string: extraStr,
            attributes: [
                .foregroundColor: balanceColor(positive: extraSeconds >= 0),
                .font: NSFont.boldSystemFont(ofSize: 13)
            ]
        )
        sub.addItem(extraItem)

        return sub
    }

    private func buildWeeklyStatsMenu() -> NSMenu {
        let sub = NSMenu()
        let cal = Calendar.current

        // Gather all history entries + today
        let dayData = gatherDayData()

        // Group by ISO week (Mon–Sun)
        var weeks: [String: [(date: Date, seconds: Double)]] = [:]
        for entry in dayData {
            let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date))!
            let key = dateFmt.string(from: monday)
            weeks[key, default: []].append(entry)
        }

        let sortedKeys = weeks.keys.sorted().reversed()

        if weeks.isEmpty {
            sub.addItem(NSMenuItem(title: "No data yet", action: nil, keyEquivalent: ""))
            return sub
        }

        for weekKey in sortedKeys.prefix(8) {
            guard let entries = weeks[weekKey],
                  let weekStart = dateFmt.date(from: weekKey) else { continue }
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            let startStr = dateFmt.string(from: weekStart)
            let endStr = dateFmt.string(from: weekEnd)

            var extraSeconds: Double = 0
            var totalSeconds: Double = 0
            var dayCount = 0

            for entry in entries {
                totalSeconds += entry.seconds
                dayCount += 1
                let weekday = cal.component(.weekday, from: entry.date) // 1=Sun, 7=Sat
                let isWeekend = weekday == 1 || weekday == 7

                if isWeekend {
                    extraSeconds += entry.seconds
                } else {
                    extraSeconds += entry.seconds - workdayThreshold
                }
            }

            let absExtra = abs(Int(extraSeconds))
            let extraH = absExtra / 3600
            let extraM = (absExtra % 3600) / 60
            let totalH = Int(totalSeconds) / 3600
            let totalM = (Int(totalSeconds) % 3600) / 60
            let sign = extraSeconds >= 0 ? "+" : "-"

            let header = NSMenuItem(title: "\(startStr) → \(endStr)", action: nil, keyEquivalent: "")
            header.attributedTitle = NSAttributedString(
                string: "\(startStr) → \(endStr)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
            sub.addItem(header)
            sub.addItem(NSMenuItem(title: "  Total: \(String(format: "%02d:%02d", totalH, totalM))  (\(dayCount) days)", action: nil, keyEquivalent: ""))

            let extraStr = "  Balance: \(sign)\(String(format: "%02d:%02d", extraH, extraM))"
            let extraItem = NSMenuItem(title: extraStr, action: nil, keyEquivalent: "")
            extraItem.attributedTitle = NSAttributedString(
                string: extraStr,
                attributes: [
                    .foregroundColor: balanceColor(positive: extraSeconds >= 0),
                    .font: NSFont.boldSystemFont(ofSize: 13)
                ]
            )
            sub.addItem(extraItem)
            sub.addItem(NSMenuItem.separator())
        }

        return sub
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
