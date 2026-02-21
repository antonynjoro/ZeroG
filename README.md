# 🧑‍🚀 ZeroG

**Open Source Voice Typing for macOS**

> **"The voice typing tool so good, you'll forget how to type."**

---

## 🛰️ The Manifesto

**We don't type. We transmit.**

ZeroG was born from the realization that typing is a bottleneck. It is a terrestrial limitation. We spent decades training our fingers to hit 100 Words Per Minute (WPM), only to realize that the speed of thought is infinite.

ZeroG is not just a dictation tool. It is an evolutionary step. Just as an astronaut in orbit unlearns the physics of gravity—expecting a pen to float rather than fall—ZeroG users unlearn the friction of the keyboard.

We are building the "Air Gap" for your thoughts: **Private. Local. Weightless.**

---

## 🚀 Flight Systems (Features)

- **Zero Friction**: Leverages **Apple Silicon MLX** for near-instant transcription. 0 WPM. 100% Output.
- **Vacuum Sealed**: By default, **sound doesn't travel**. Audio is processed locally on your hardware. No data leaves the ship.
- **Universal Comms**: Hold `Left Control` to transmit thought into *any* application.
- **Auto-Pilot**: Press `Left Control`, speak freely, and let the **Silence Detection** sensor cut the feed when you're done.
- **Gravity Assist** (Optional): Hold `Control + Q` to engage **Gemini** thrusters for grammar correction and formatting.
- **Flight Recorder**: A native "Glass" HUD that floats above your dock.

![ZeroG HUD](./ZeroG_Logo.png)
*(Note: Visuals undergoing orbital refit)*

---

## 🛠️ Pre-Flight Check (Installation)

### Prerequisites
- macOS 12+ (Apple Silicon recommended for optimal thrust)
- Python 3.11+
- [Git](https://git-scm.com/)

### 1. Board the Ship
```bash
git clone https://github.com/antonynjoro/MacDictate.git
cd MacDictate
./setup.sh
```

### 2. Clearance Codes (Permissions)
Upon first launch, macOS will request clearance for:
- **Microphone**: Audio input feed.
- **Accessibility**: To detect the manual override key (Left Control).
- **System Events**: To inject the payload (text) into target fields.

### 3. Takeoff
Launch the sequence:
```bash
python main.py
```
You will see a microphone icon in your Status Bar.
- **Transmit**: Hold `Left Control`. The HUD will appear. Speak. Release to paste.
- **Hands-Free**: Press `Left Control`. Speak. The system detects the vacuum (silence) and auto-cuts the feed.
- **Polished Transmission**: Hold `Left Control + Q`. Speak. Release.

### 4. Deploy Automator Beacon
To run ZeroG without an open terminal channel:

1. Open **Automator** -> New **Application**.
2. Add **Run Shell Script**.
3. Paste the ignition sequence:

```bash
# Path to your ZeroG launchpad
PROJECT_DIR="/Users/antony/Documents/Projects/MacDictate"

# 1. Clear airspace
pkill -f "main.py" || true
sleep 0.5

# 2. Navigate to launchpad
cd "$PROJECT_DIR"

# 3. Silent launch
nohup ./.venv/bin/python main.py >/dev/null 2>&1 &
```

4. Save as **ZeroG**.

---

## 🕹️ Flight Controls (Configuration)

ZeroG uses Environment Variables for flight adjustments.

### Flight Recorder (Logging)
By default, the Black Box is **OFF** (`DEBUG=False`) for maximum privacy.
To enable telemetry:
1. Create `.env`.
2. Add `DEBUG=True`.
3. Reboot systems.

### Gravity Assist (Gemini API)
For "Smart Formatting":
1. Acquire Clearance Key from [Google AI Studio](https://aistudio.google.com/).
2. Add to `.env`: `GOOGLE_API_KEY=your_key_here`

---

## ⚠️ Turbulence (Troubleshooting)

### Payload Failure (Not Pasting)
- Check **System Settings > Privacy & Security > Accessibility**.
- If `ZeroG` (or Terminal/Python) is listed, **REMOVE** it (-) and re-add. Old clearance codes expire.

### Dead Air (No Audio)
- Check **System Settings > Privacy & Security > Microphone**.
- Ensure we have a lock on your comms.

---

## 🧪 R&D (Development)

### Run Diagnostics
```bash
python -m pytest tests/
```

### Blueprint
- `zerog/core`: Core physics engine (State machine, Recorder).
- `zerog/gui`: Visual interface (HUD).
- `tests/`: Simulation scenarios.

---

## 📅 Captain's Log

### [v0.10.0] - 2026-02-20
- **Parallel Chunk Transcription**: Audio is now chunked and transcribed dynamically in the background while you speak, massively reducing wait-time latency for long dictations without losing context.

### [v0.9.0] - 2026-01-03
- **Rebrand**: Initiated "ZeroG" protocol.
- **Brand Guide**: Published `BRANDING.md` for all contributors.

### [v0.8.1] - 2026-01-02
- **Hands-Free**: Autos stop on silence.

### [v0.8.0] - 2026-01-02
- **Universal Injection**: "FastTyper" module for compatibility across all sectors.

---
*ZeroG: Don't let gravity hold back your thoughts.*
