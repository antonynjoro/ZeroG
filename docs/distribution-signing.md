# Signing & Notarizing ZeroG for Direct Distribution

ZeroG **cannot** ship on the Mac App Store — it relies on a global `CGEvent` tap
and synthetic Cmd+V injection, both of which require the sandbox to be disabled
(see [`app-store-readiness-audit.md`](app-store-readiness-audit.md)). The
supported path is **direct download**: a `.app` signed with a *Developer ID
Application* certificate and **notarized** by Apple, so Gatekeeper opens it
cleanly on any Mac.

This is a one-time setup. After it, every release is a single `build_app.sh`
invocation.

---

## One-time setup

### 1. Create a Developer ID Application certificate

Your App Store app uses an *Apple Distribution* certificate. Direct download
needs a **different** one. You have the paid membership already, so this is free.

1. https://developer.apple.com/account → **Certificates, IDs & Profiles** →
   **Certificates** → **+**
2. Choose **Developer ID Application** → Continue.
3. Follow the CSR step (Keychain Access → Certificate Assistant → *Request a
   Certificate from a Certificate Authority*), upload it, download the cert.
4. Double-click the downloaded `.cer` to install it into your login Keychain.

Verify it's installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see a line like:

```
2) ABC123… "Developer ID Application: Your Name (TEAMID)"
```

Copy that full quoted string — it's your `ZEROG_SIGN_IDENTITY`.

### 2. Store notarization credentials (notarytool keychain profile)

Create an **app-specific password** (NOT your Apple ID password) at
https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.

Find your **Team ID** at https://developer.apple.com/account (Membership page,
10 characters).

Store the credentials once in the Keychain under a named profile:

```bash
xcrun notarytool store-credentials "zerog-notary" \
    --apple-id "antonynjoro@gmail.com" \
    --team-id "YOURTEAMID" \
    --password "abcd-efgh-ijkl-mnop"   # the app-specific password
```

`"zerog-notary"` is your `ZEROG_NOTARY_PROFILE`. The password is stored
encrypted in the Keychain — it is never placed in the build script or the repo.

---

## Building a release

```bash
cd ZeroGSwift
ZEROG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ZEROG_NOTARY_PROFILE="zerog-notary" \
./build_app.sh
```

The script will:
1. Build the release binary and assemble `build/ZeroG.app`.
2. `codesign` the app with hardened runtime + the entitlements.
3. Zip it, submit to `notarytool --wait` (typically 1–5 minutes), and `staple`
   the ticket so it validates offline.

### Build modes (no script edits needed)

| Environment | Result |
|---|---|
| _(none set)_ | Unsigned local dev build |
| `ZEROG_SIGN_IDENTITY` only | Signed, hardened runtime — not notarized |
| `ZEROG_SIGN_IDENTITY` + `ZEROG_NOTARY_PROFILE` | Signed + notarized + stapled (shippable) |

---

## Verify a shippable build

```bash
# Should print: accepted / source=Notarized Developer ID
spctl -a -vv -t exec build/ZeroG.app

# Should print: The validation was successful
xcrun stapler validate build/ZeroG.app
```

If both pass, the `.app` can be zipped and put on the website — users download,
unzip, drag to Applications, and open with no Gatekeeper warning.

---

## Distributing on the website

Ship a **zip** of the stapled `.app` (`ditto -c -k --keepParent ZeroG.app
ZeroG.zip`), or a signed/notarized `.dmg` if you want the drag-to-Applications
window. Either way the artifact must be the **stapled** bundle from a full
release build.

> First launch still prompts for **Input Monitoring**, **Accessibility**, and
> **Microphone** in System Settings → Privacy & Security. That's normal for this
> class of app — the landing page should show users where to grant them.

---

## Notes / gotchas

- **Hardened runtime is mandatory for notarization** and is applied by the
  script (`--options runtime`). Don't remove it.
- The app is intentionally **not sandboxed** (`com.apple.security.app-sandbox`
  = `false`). That's compatible with Developer ID + notarization; it's only
  incompatible with the App Store.
- WhisperKit is statically linked, so the bundle has a single Mach-O. If a
  future dependency adds a `.framework`/`.dylib`, it must be signed too — sign
  nested code inside-out before the app.
- Notarization staples a ticket into the `.app`; always distribute the build
  produced **after** stapling, not an earlier copy.
