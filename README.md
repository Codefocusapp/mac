# CodeFocus — Mac Setup

Connects **Claude Code** (or another AI coding agent) on your Mac to the **CodeFocus** iPhone app over Bluetooth.
Your phone unlocks while your agent is working — and locks again the moment it stops.

## Install

Paste this into your Mac's **Terminal** and hit Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/codefocusapp/mac/main/install.sh | bash
```

> Tip: hover the code block above and click the 📋 copy button.

## What it does

- Compiles a tiny Bluetooth peripheral locally — no notarization, fully readable source.
- Adds hooks to your `~/.claude/settings.json` so it knows when your agent is active (your existing hooks stay untouched).
- Installs a LaunchAgent so it runs automatically at login.

When everything's set up, open the **CodeFocus** app on your iPhone and connect.

## Requirements

- macOS
- [Claude Code](https://claude.com/claude-code)
- Xcode Command Line Tools — install with `xcode-select --install`

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/app.earned.peripheral.plist
rm -rf ~/.earned ~/Library/LaunchAgents/app.earned.peripheral.plist
```

100% local & open source — nothing runs through third-party servers.
