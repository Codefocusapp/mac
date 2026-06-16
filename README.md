# CodeFocus — Setup

CodeFocus locks your distracting apps unless your AI coding agent is working.
Setup has **two parts**: the iPhone app and a one-line Mac command.

## 1. Get the app

Download **CodeFocus** from the App Store on your iPhone:

**📱 [ Download CodeFocus on the App Store ]**

*(App Store link goes live at launch.)*

## 2. Connect your Mac

Paste this into your Mac's **Terminal** and hit Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/codefocusapp/setup/main/install.sh | bash
```

> Tip: hover the code block and click the 📋 copy button.

This compiles a tiny Bluetooth peripheral locally, hooks into Claude Code so it knows when your agent is active (your existing hooks stay untouched), and runs automatically at login. Fully local, readable source.

## 3. Pair

Open the **CodeFocus** app, allow Screen Time + Bluetooth, and connect to your Mac. Done — your phone now unlocks while your agent codes, and locks when it stops.

## Requirements

- iPhone + the CodeFocus app
- macOS
- [Claude Code](https://claude.com/claude-code) (or another supported agent)
- Xcode Command Line Tools — `xcode-select --install`

## Uninstall (Mac side)

```bash
launchctl unload ~/Library/LaunchAgents/app.earned.peripheral.plist
rm -rf ~/.earned ~/Library/LaunchAgents/app.earned.peripheral.plist
```

100% local & open source — nothing runs through third-party servers.
