#!/bin/bash
#
# CodeFocus — Mac Setup
# Verbindet Claude Code mit der CodeFocus iPhone-App über Bluetooth.
# Nutzung:  curl -fsSL https://raw.githubusercontent.com/codefocusapp/setup/main/install.sh | bash
#
set -e

CF_DIR="$HOME/.codefocus"
CLAUDE_DIR="$HOME/.claude"
STATE_FILE="$CLAUDE_DIR/claude-state"
SETTINGS="$CLAUDE_DIR/settings.json"
PLIST="$HOME/Library/LaunchAgents/app.codefocus.peripheral.plist"
APP="$CF_DIR/CodeFocus.app"
BIN="$APP/Contents/MacOS/CodeFocus"
SRC="$CF_DIR/CodeFocus.swift"
LOG="$CF_DIR/codefocus.log"
# Alt-Setup (frühere "Earned"-Version) zum Aufräumen
OLD_DIR="$HOME/.earned"
OLD_PLIST="$HOME/Library/LaunchAgents/app.earned.peripheral.plist"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "\033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[33m!\033[0m %s\n" "$1"; }
die()  { printf "\033[31m✗ %s\033[0m\n" "$1"; exit 1; }

echo ""
bold "🔒 CodeFocus — Mac Setup"
echo "Verbindet Claude Code mit deiner CodeFocus iPhone-App."
echo ""

# ---------- 1. Checks ----------
[ "$(uname)" = "Darwin" ] || die "Earned läuft nur auf macOS."

if ! command -v swiftc >/dev/null 2>&1; then
  warn "Xcode Command Line Tools fehlen (für die Kompilierung)."
  echo "  Bitte ausführen:  xcode-select --install"
  echo "  Danach dieses Script erneut starten."
  die "swiftc nicht gefunden."
fi
ok "Xcode Command Line Tools gefunden"

if [ ! -d "$CLAUDE_DIR" ]; then
  warn "Claude Code scheint nicht installiert (~/.claude fehlt)."
  echo "  Earned braucht Claude Code. Installiere es zuerst: https://claude.com/claude-code"
  die "Claude Code nicht gefunden."
fi
ok "Claude Code gefunden"

PYTHON="$(command -v python3 || true)"
[ -n "$PYTHON" ] || die "python3 nicht gefunden (kommt mit Xcode CLT)."

# Alt-Setup (frühere "Earned"-Version) aufräumen
launchctl unload "$OLD_PLIST" 2>/dev/null || true
rm -rf "$OLD_DIR" "$OLD_PLIST" 2>/dev/null || true

mkdir -p "$APP/Contents/MacOS" "$HOME/Library/LaunchAgents"

# ---------- 2. BLE-Peripheral schreiben ----------
bold "Installiere BLE-Peripheral…"
cat > "$SRC" <<'SWIFTEOF'
import Foundation
import CoreBluetooth

let kServiceUUID        = CBUUID(string: "CC1A0DE0-0000-1000-8000-00805F9B34FB")
let kCharacteristicUUID = CBUUID(string: "CC1A0DE0-0001-1000-8000-00805F9B34FB")
let kStatePath   = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/claude-state")
let kSessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sessions")

// Liest Claude Codes EIGENE Session-Status-Dateien: ~/.claude/sessions/<pid>.json.
// active(1) = irgendeine interaktive CLI-Session hat status "busy" (und der Prozess lebt).
// "busy" steht den GANZEN Turn an — auch beim Denken/Plan-Mode (kein Timeout, keine
// Fehl-Locks) — und flippt bei Fertigwerden UND bei ESC innerhalb ~1-2s auf "idle".
// SDK-Sessions (z.B. claude-mem Observer, entrypoint "sdk-cli") werden ignoriert.
func readState() -> UInt8 {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: kSessionsDir) else { return 0 }
    for name in files where name.hasSuffix(".json") {
        let path = (kSessionsDir as NSString).appendingPathComponent(name)
        guard let data = fm.contents(atPath: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["entrypoint"] as? String) == "cli",
              (obj["status"] as? String) == "busy"
        else { continue }
        // Prozess noch am Leben? Verhindert hängendes "busy" nach Crash/Kill.
        if let pid = obj["pid"] as? Int, kill(pid_t(pid), 0) != 0 { continue }
        return 1
    }
    return 0
}

final class Peripheral: NSObject, CBPeripheralManagerDelegate {
    var manager: CBPeripheralManager!
    var characteristic: CBMutableCharacteristic!
    var last: UInt8 = 255
    var advertising = false

    func start() {
        // Initialen Zustand für den Simulator-Bridge schreiben (Host liest claude-state).
        try? (readState() == 1 ? "active" : "idle").write(toFile: kStatePath, atomically: true, encoding: .utf8)
        manager = CBPeripheralManager(delegate: self, queue: nil)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }
    func poll() {
        guard advertising else { return }
        let v = readState()
        characteristic.value = Data([v])   // immer aktuell halten — fürs aktive Re-Read vom iPhone
        if v != last {
            // claude-state für den Simulator-Bridge spiegeln (Host liest diese Datei)
            try? (v == 1 ? "active" : "idle").write(toFile: kStatePath, atomically: true, encoding: .utf8)
            // updateValue kann false liefern (Sende-Queue voll). Dann last NICHT setzen,
            // damit der nächste Poll den Notify erneut versucht (statt ihn zu verschlucken).
            if manager.updateValue(Data([v]), for: characteristic, onSubscribedCentrals: nil) {
                last = v
            }
        }
    }
    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        let names = ["unknown","resetting","unsupported","unauthorized","poweredOff","poweredOn"]
        let s = p.state.rawValue
        print("Earned: Bluetooth-Status =", s >= 0 && s < names.count ? names[s] : "\(s)")
        if p.state == .unauthorized {
            print("Earned: ⚠️ Keine Bluetooth-Erlaubnis. Systemeinstellungen → Datenschutz → Bluetooth → earned-ble aktivieren.")
        }
        guard p.state == .poweredOn else { return }
        last = readState()
        characteristic = CBMutableCharacteristic(type: kCharacteristicUUID,
            properties: [.read, .notify], value: nil, permissions: [.readable])
        let svc = CBMutableService(type: kServiceUUID, primary: true)
        svc.characteristics = [characteristic]
        manager.add(svc)
    }
    func peripheralManager(_ p: CBPeripheralManager, didAdd s: CBService, error: Error?) {
        // Echten Mac-Namen senden, damit das iPhone im "Choose your Mac"-Picker
        // den richtigen Mac erkennt (statt generisch "ClaudeMac").
        let name = Host.current().localizedName ?? "Mac"
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [kServiceUUID],
            CBAdvertisementDataLocalNameKey: name
        ])
        advertising = true
    }
    func peripheralManager(_ p: CBPeripheralManager, didReceiveRead r: CBATTRequest) {
        r.value = Data([readState()])
        manager.respond(to: r, withResult: .success)
    }
    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
        didSubscribeTo c: CBCharacteristic) {
        last = readState()
        manager.updateValue(Data([last]), for: characteristic, onSubscribedCentrals: [central])
    }
}

let p = Peripheral()
p.start()
RunLoop.main.run()
SWIFTEOF

swiftc -O "$SRC" -o "$BIN" || die "Kompilierung fehlgeschlagen."
ok "BLE-Peripheral kompiliert"

# App-Bundle-Identität → Bluetooth-Dialog zeigt "CodeFocus" + eigene Erklärung
cat > "$APP/Contents/Info.plist" <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CodeFocus</string>
  <key>CFBundleDisplayName</key><string>CodeFocus</string>
  <key>CFBundleIdentifier</key><string>app.codefocus.peripheral</string>
  <key>CFBundleExecutable</key><string>CodeFocus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>CodeFocus connects to your iPhone over Bluetooth to share when Claude Code is working.</string>
</dict>
</plist>
PLISTEOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
ok "CodeFocus.app erstellt (Bluetooth-Dialog zeigt \"CodeFocus\")"

# ---------- 3. State-Datei + alte Mechanik aufräumen ----------
# Der Peripheral-Dienst liest Claude Codes EIGENE Session-Status (~/.claude/sessions/*.json)
# und pflegt claude-state selbst (für den Simulator-Bridge). Keine Hooks mehr nötig.
[ -f "$STATE_FILE" ] || printf idle > "$STATE_FILE"
rm -f "$CF_DIR/hook.py" 2>/dev/null || true
rm -rf "$CLAUDE_DIR/codefocus-sessions" 2>/dev/null || true

# ---------- 4. Frühere CodeFocus-Hooks entfernen ----------
# Neuer Ansatz braucht keine Hooks — unsere alten Einträge (printf claude-state / hook.py)
# werden entfernt, fremde Hooks bleiben unangetastet.
bold "Räume frühere Hooks auf…"
"$PYTHON" - "$SETTINGS" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
try:
    cfg = json.load(open(path))
except Exception:
    sys.exit(0)
hooks = cfg.get("hooks", {})

def strip_ours(arr):
    out = []
    for group in arr:
        kept = [h for h in group.get("hooks", [])
                if "claude-state" not in h.get("command", "")
                and "codefocus/hook.py" not in h.get("command", "")]
        if kept:
            group["hooks"] = kept
            out.append(group)
    return out

for ev in ("UserPromptSubmit", "Stop", "SessionEnd", "Notification"):
    if ev in hooks:
        hooks[ev] = strip_ours(hooks[ev])
        if not hooks[ev]:
            del hooks[ev]

json.dump(cfg, open(path, "w"), indent=2)
print("cleaned")
PYEOF
ok "Frühere Hooks entfernt (Status-Datei-Ansatz braucht keine Hooks)"

# ---------- 5. LaunchAgent (Autostart) ----------
bold "Richte Autostart ein…"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>app.codefocus.peripheral</string>
  <key>ProgramArguments</key>
  <array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST" 2>/dev/null || true
ok "Autostart eingerichtet (läuft ab jetzt bei jedem Login)"

# ---------- 6. Fertig ----------
echo ""
bold "✅ Fertig!"
echo ""
bold "Beim ersten Start fragt macOS nach Bluetooth-Erlaubnis → bitte erlauben."
echo "(Falls kein Dialog kommt: Systemeinstellungen → Datenschutz → Bluetooth → CodeFocus aktivieren)"
echo ""
bold "Öffne jetzt die CodeFocus-App auf deinem iPhone und verbinde dich."
echo ""
echo "Status:    tail -f $LOG"
echo "Entfernen: launchctl unload $PLIST && rm -rf $CF_DIR \"$PLIST\""
echo ""
