# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZeroG is a privacy-focused voice typing application for macOS that leverages local Apple Silicon MLX models for real-time speech transcription. The application uses a space/aerospace theme and terminology throughout its codebase and documentation.

## Development Commands

### Setup and Installation
```bash
# Install dependencies and set up virtual environment
./setup.sh

# Activate virtual environment manually if needed
source .venv/bin/activate

# Install requirements manually
pip install -r requirements.txt
```

### Running the Application
```bash
# Main entry point - starts the complete application
python main.py

# Alternative using shell script
./run_zerog.sh
```

### Testing
```bash
# Run all tests
python -m pytest tests/

# Run specific test files
python -m pytest tests/test_main.py
python -m pytest tests/test_state.py
python -m pytest tests/test_gui_integration.py

# Manual testing scripts
python tests/manual_test_sound.py
python tests/verify_injection.py
```

### Building
```bash
# Build macOS app bundle using py2app
python setup.py py2app
```

## Architecture Overview

### Core Application Structure

**Main Entry Point**: `main.py`
- Sets up logging based on DEBUG environment variable
- Loads environment variables from `.env`
- Initializes and runs the main application

**Application Controller**: `zerog/app.py` 
- `ZeroGApp` class manages the Cocoa application lifecycle
- Coordinates between core recording logic and GUI components
- Initializes AudioRecorder, KeyMonitor, StatusMenuController, and HUDController

### Core Modules (`zerog/core/`)

**State Management**: `state.py`
- Singleton `StateMachine` class using Observer pattern
- Thread-safe state transitions: IDLE → RECORDING → PROCESSING → SUCCESS/ERROR
- Separate audio level broadcasting system for real-time feedback
- Global `state_machine` instance used throughout the application

**Audio Recording**: `recorder.py`
- `AudioRecorder` class handles MLX Whisper model integration
- Real-time audio capture with silence detection
- Automatic transcription with configurable silence thresholds

**Input Handling**: `input.py`
- `KeyMonitor` class for global hotkey detection (Left Control key)
- Supports both hold-to-record and press-to-start modes
- Handles Control+Q combination for Gemini-enhanced processing

**Text Processing**: `gemini.py`
- Optional Gemini API integration for grammar correction and formatting
- Uses prompt template from `gemini_prompt.txt`
- Requires `GOOGLE_API_KEY` environment variable

**Text Injection**: `typer.py` and `clipboard.py`
- Multiple text injection strategies for compatibility
- `FastTyper` handles direct text injection
- Clipboard-based fallback for better app compatibility

### GUI Components (`zerog/gui/`)

**Status Menu**: `menu.py`
- `StatusMenuController` manages the macOS status bar icon
- Provides access to application controls and settings

**HUD Interface**: `hud.py`
- `HUDController` creates floating heads-up display
- Real-time visual feedback during recording
- Audio level visualization and state indicators

### Configuration

**Environment Variables** (`.env` file):
- `DEBUG=True/False` - Enables detailed logging to `mac_dictate.log`
- `GOOGLE_API_KEY=your_key` - Required for Gemini API features

**Logging**:
- Debug logging writes to `mac_dictate.log` in project root
- Only enabled when `DEBUG=True` in environment

### Key Design Patterns

1. **Observer Pattern**: StateMachine broadcasts state changes to registered observers
2. **Singleton Pattern**: StateMachine ensures single source of truth for application state
3. **Strategy Pattern**: Multiple text injection methods with fallback hierarchy
4. **Event-Driven Architecture**: Key events trigger state transitions and UI updates

### Dependencies

Core dependencies include:
- `mlx-whisper` - Local speech recognition using Apple Silicon
- `sounddevice` - Audio input capture
- `pyobjc-framework-*` - macOS Cocoa/Quartz integration
- `google-genai` - Optional Gemini API integration
- `python-dotenv` - Environment variable management

### Testing Strategy

Tests are organized by component:
- `test_main.py` - Integration tests for main application flow
- `test_state.py` - State machine behavior and thread safety
- `test_gui_integration.py` - GUI component integration
- `test_core_injection.py` - Text injection mechanisms
- Manual test files for audio and injection verification