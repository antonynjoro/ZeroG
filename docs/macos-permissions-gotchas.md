# macOS Permissions Gotchas (TCC) — hard-won findings

Field notes from building the permissions onboarding wizard (2026-06-10, branch
`feature/permissions-onboarding`). Several of these cost hours of debugging and
multiple wrong fixes. Read this before touching `PermissionsManager`,
`KeyMonitor`, `OnboardingWindow`, or anything TCC-adjacent.

## 1. `CGEvent.tapCreate(.listenOnly)` succeeding is NOT a permission signal

macOS will **create the tap successfully while silently withholding events**
until the process is trusted. Two separate implementations advanced the
onboarding wizard prematurely because they treated "tap installed" as proof
of a grant. It proves nothing.

- ✅ Detect Accessibility with `AXIsProcessTrusted()` (non-prompting, poll-safe).
- ❌ Never infer a grant from `tapCreate` returning non-nil.
- `tapCreate` is still the right call *after* a grant to bring the hotkey up —
  just never as a check.

## 2. ZeroG needs only TWO permissions — do not reintroduce Input Monitoring

An Accessibility-trusted process may create listen-only CGEvent taps. So
Accessibility covers BOTH trigger-key detection AND the Cmd+V paste. Proven
live: the hotkey works with ZeroG entirely absent from the Input Monitoring
pane. The wizard is Welcome → Mic → Accessibility → Trigger key → Done.

`CGPreflightListenEventAccess()` is moot now, but for the record: it caches
`false` per-process and never reports a live grant — useless for polling.

## 3. `AXIsProcessTrusted()` caches TRUE per running process

A running process that was ever trusted keeps reading `true` after
`tccutil reset Accessibility` — the revoke is invisible until relaunch.

**Testing protocol (order matters):**
```bash
# 1. QUIT ZeroG completely first (menu bar → Quit)
tccutil reset Microphone com.zerog.app
tccutil reset Accessibility com.zerog.app
open ZeroGSwift/build/ZeroG.app   # bundled app only — swift run attributes TCC to Terminal
```
Resetting while the app runs = chasing ghosts. Also: revoking Microphone while
the app runs gets the process KILLED by TCC (expected, not a crash).

## 4. Mic is the odd one out: tri-state, and `requestAccess` no-ops when denied

`AVCaptureDevice.requestAccess` only shows a dialog from `.notDetermined`.
From `.denied` it returns false with NO dialog — the user is stuck unless you
branch `.denied` to the Settings deep link. Never render a uniform "Allow"
button for mic.

## 5. Activation-policy flips kill the event tap

The wizard switches `.accessory → .regular` (Dock icon) on show and back on
close. That switch leaves the CGEvent tap dead — hotkey stops until relaunch.
Fix in place: `onClose` rebuilds the tap (`stop()` + `start()`) on the next
runloop turn after the policy settles. Any future policy flip needs the same.

## 6. Logging that actually reaches Console

- `print()` → stdout only; invisible for a Finder/`open`-launched GUI app.
- `NSLog("%@", msg)` → redacted to `<private>` in the unified log.
- ✅ `NSLog("%{public}@", msg)` — what `Log.error` does now.

Live-tail: `log stream --predicate 'process == "ZeroG" AND eventMessage BEGINSWITH "[Permissions]"'`

## 7. Misc first-run traps

- Reading any file under `~/Documents`/Desktop/Downloads (e.g. a `.env` next
  to a dev build) triggers the "ZeroG would like to access files in your
  Documents folder" prompt before onboarding even starts. `Config.loadDotEnv`
  skips protected folders for this reason.
- `AXIsProcessTrustedWithOptions(prompt: true)` pre-lists the app in the
  Accessibility pane (toggle ready, no "+ and hunt") — fire it once on the
  user's button tap, never on a poll timer (the prompting variants spawn a
  dialog per call).
- TCC pane deep links (`x-apple.systempreferences:…`) drift across macOS
  versions (broke in Tahoe). They live ONLY in `PermissionKind.settingsURL`.
