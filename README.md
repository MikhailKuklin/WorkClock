# WorkClock

A lightweight macOS menubar app that tracks your daily work hours. No accounts, no projects, no cloud — just a simple timer that shows how long you've been working today.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- Displays elapsed work time in the menubar (`⏱ 04:23:15`)
- **Pauses automatically** when you lock the screen or Mac goes to sleep
- **Resumes automatically** when you unlock or wake up
- **Manual pause/resume** — pause the timer for personal breaks (icon changes to `⏸`)
- **Persists across logout/login** and app restarts
- **Resets automatically** each new day
- **Keeps daily history** — view the last 14 days from the menubar
- Color indicators: **orange at 8h**, **red at 10h**
- Single Swift file, no dependencies

## Install

### Option 1: Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/MikhailKuklin/WorkClock.git
cd WorkClock
make install
```

### Option 2: Manual build

```bash
git clone https://github.com/MikhailKuklin/WorkClock.git
cd WorkClock
swiftc -o WorkClock WorkClock.swift -framework Cocoa
mkdir -p WorkClock.app/Contents/MacOS
cp WorkClock WorkClock.app/Contents/MacOS/
cp Info.plist WorkClock.app/Contents/
cp -r WorkClock.app /Applications/
open /Applications/WorkClock.app
```

## Start on login

Copy the launch agent to auto-start WorkClock on login:

```bash
make autostart
```

Or manually:

```bash
cp com.workclock.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.workclock.plist
```

## Usage

- The timer starts when the app launches and counts your active (unlocked) time
- **Click** the menubar icon for options:
  - **Pause/Resume** — manually pause for breaks; screen unlock won't auto-resume while paused
  - **History** — view daily totals for the last 14 days
  - **Reset** — reset today's timer to zero
  - **Quit** — stop the app

## Data files

| File | Purpose |
|------|---------|
| `~/.workclock_state` | Current day's accumulated time |
| `~/.workclock_history` | Daily totals log (`YYYY-MM-DD  HH:MM:SS`) |

## Uninstall

```bash
make uninstall
```

Or manually:

```bash
pkill -f WorkClock.app
launchctl unload ~/Library/LaunchAgents/com.workclock.plist
rm ~/Library/LaunchAgents/com.workclock.plist
rm -rf /Applications/WorkClock.app
rm ~/.workclock_state ~/.workclock_history
```

## License

MIT
