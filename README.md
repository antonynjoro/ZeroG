# ZeroG

Privacy-focused voice typing for macOS.

Hold **Left Control** to record, release to transcribe and paste into the active app. Hold **Control + Q** while recording to optionally polish the transcription with Gemini.

## Requirements

- macOS 14+
- Xcode with Swift 5.9+ toolchain
- Apple Silicon recommended for WhisperKit performance

## Development

```bash
cd ZeroGSwift
swift test
swift run
```

## Build

```bash
cd ZeroGSwift
swift build -c release
./build_app.sh
```

The packaged app is written to:

```text
ZeroGSwift/build/ZeroG.app
```

## Configuration

ZeroG reads configuration from environment variables and `UserDefaults`.

- `DEBUG=true` enables debug logging.
- `GOOGLE_API_KEY=...` enables optional Gemini polishing.

In packaged app use, the Gemini key can be set from the menu bar item.

## Permissions

Grant these in **System Settings -> Privacy & Security**:

- Microphone
- Accessibility
- Input Monitoring

## Testing and CI

The active implementation is Swift-only. CI runs on macOS and executes:

```bash
cd ZeroGSwift
swift package resolve
swift test
swift build -c release
./build_app.sh
```

The legacy Python implementation and Python tests have been removed from the active tree.
