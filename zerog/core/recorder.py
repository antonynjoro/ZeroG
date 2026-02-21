import numpy as np
import sounddevice as sd
import pyperclip
import mlx_whisper
import logging
import os
from pathlib import Path
import Cocoa
import Quartz
import time
import queue
import threading
import subprocess
from .state import state_machine, AppState
from . import gemini
import sys
import gc

logger = logging.getLogger(__name__)

# Constants - 4-bit quantized whisper-medium for faster speed
MODEL_PATH = "mlx-community/whisper-medium-mlx-4bit"
SAMPLE_RATE = 16000
SOUND_FILE = "/System/Library/Sounds/Pop.aiff"
SILENCE_THRESHOLD = 0.015  # RMS amplitude below which is considered silence
SILENCE_DURATION = 5.0    # Seconds of silence to trigger auto-stop
CHUNK_MIN_DURATION = 15.0  # Min duration before evaluating for silence boundaries
CHUNK_MAX_DURATION = 25.0 # Max duration of a single chunk before forcing transcription
WHISPER_PAD_DURATION = 8.0 # Pad clips shorter than this to force Whisper's fast execution path


class AudioRecorder:
    def __init__(self):
        self.recording = False
        self.audio_queue = queue.Queue()
        self.stream = None
        self._lock = threading.Lock()
        self.reset_timer = None
        self._model_dir = None  # Cached resolved model path
        self._preloaded_sound = None  # Pre-loaded sound effect
        self._preloaded_sound = None  # Pre-loaded sound effect
        self._preloaded_sound = None  # Pre-loaded sound effect
        self._processing_start_time = None  # For latency tracking
        
        # Parallel transcription state
        self.transcribed_text_buffer = []
        self.last_context = "The user is dictating. Valid English text."
        self.bg_transcriber_thread = None
        self.stop_transcribing_event = threading.Event()
        
        # Silence detection
        self._silence_start_time = None
        self._triggered_silence_stop = False
        
        state_machine.add_observer(self.on_state_change)
        threading.Thread(target=self._initialize_all, daemon=True).start()

    def _warmup_audio_subsystem(self):
        """Pre-initialize audio input to eliminate cold-start delay."""
        try:
            # Create a short-lived stream to warm up sounddevice/CoreAudio
            warmup_stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1)
            warmup_stream.start()
            time.sleep(0.1)  # Brief activation to fully initialize
            warmup_stream.stop()
            warmup_stream.close()
            logger.info("Audio subsystem warmup complete.")
        except Exception as e:
            logger.warning(f"Audio warmup failed: {e}")
        
        # Pre-load the sound effect (must run on main thread for Cocoa)
        try:
            self._preloaded_sound = Cocoa.NSSound.soundNamed_("Pop")
            if self._preloaded_sound:
                logger.info("Sound effect pre-loaded.")
        except Exception as e:
            logger.warning(f"Sound preload failed: {e}")

    def _initialize_all(self):
        """Initialize audio subsystem and models in background."""
        # Warmup audio first (faster, unblocks recording quickly)
        self._warmup_audio_subsystem()
        # Then load the Whisper model
        self._initialize_models()

    def _initialize_models(self):
        logger.info(f"Loading MLX Whisper Model ({MODEL_PATH})...")
        try:
            from huggingface_hub import snapshot_download
            model_dir = Path(snapshot_download(MODEL_PATH))
            self._model_dir = str(model_dir)  # Cache for reuse
            
            weights_path = model_dir / "weights.safetensors"
            model_path_file = model_dir / "model.safetensors"
            
            if not weights_path.exists() and model_path_file.exists():
                logger.info("Creating symlink for mlx_whisper compatibility")
                try:
                    os.symlink(model_path_file, weights_path)
                except FileExistsError:
                    pass
                except Exception as e:
                    logger.warning(f"Failed to create symlink: {e}")

            warmup_audio = np.zeros(16000, dtype=np.float32)
            mlx_whisper.transcribe(
                warmup_audio, 
                path_or_hf_repo=self._model_dir,
                language="en",
                initial_prompt="The user is dictating. Valid English text."
            )
            logger.info("Whisper Warmup Complete.")
        except Exception as e:
            logger.error(f"Model initialization failed: {e}", exc_info=True)
            self._handle_error("Model Init Failed")



    def on_state_change(self, state, data):
        if state == AppState.RECORDING:
            self.start_recording()
        elif state == AppState.PROCESSING:
            use_gemini = data.get('use_gemini', False)
            self.stop_recording(use_gemini)

    def play_sound(self):
        # Use pre-loaded sound for instant playback, fallback to loading fresh
        sound = self._preloaded_sound or Cocoa.NSSound.soundNamed_("Pop")
        if sound:
            sound.play()
        else:
            subprocess.Popen(["afplay", SOUND_FILE])

    def callback(self, indata, frames, time_info, status):
        if self.recording:
            chunk = indata.copy()
            self.audio_queue.put(chunk)
            
            # Calculate RMS level for waveform visualization (0.0 - 1.0)
            rms = np.sqrt(np.mean(indata**2))
            
            # DEBUG: Verify we have signal
            # import sys
            # if rms > 0.01: sys.stderr.write(f"RMS: {rms:.4f}\n")

            # Normalize to 0-1 range (typical speech RMS is 0.01-0.1)
            level = float(min(1.0, rms * 10))
            # Broadcast audio level to HUD via state machine
            state_machine.broadcast_audio_level(level)

            # --- Silence Detection ---
            if rms < SILENCE_THRESHOLD:
                if self._silence_start_time is None:
                    self._silence_start_time = time.time()
                elif (time.time() - self._silence_start_time) > SILENCE_DURATION:
                    if not self._triggered_silence_stop:
                        logger.info(f"Silence detected (> {SILENCE_DURATION}s). Stopping recording.")
                        self._triggered_silence_stop = True
                        # Trigger state change in a separate thread to avoid blocking audio callback
                        use_gemini = state_machine.context.get('use_gemini', False)
                        threading.Thread(target=state_machine.set_state, args=(AppState.PROCESSING,), kwargs={'use_gemini': use_gemini}, daemon=True).start()
            else:
                # Reset silence timer if we hear sound
                self._silence_start_time = None

    def start_recording(self):
        if self.reset_timer:
            self.reset_timer.cancel()
            self.reset_timer = None
            


        with self._lock:
            if self.recording: 
                return
            if state_machine.current_state != AppState.RECORDING:
                logger.warning("State changed before recording could start, aborting")
                return
                
            logger.info("Starting Recording...")
            self.recording = True
            
            # Reset silence logic
            self._silence_start_time = None
            self._triggered_silence_stop = False
            
            # Ensure any previous transcriber thread has completely finished
            if self.bg_transcriber_thread and self.bg_transcriber_thread.is_alive():
                logger.info("Waiting for previous transcriber thread to finish before starting new recording...")
                self.stop_transcribing_event.set()
                # Do not block the lock while waiting, as the thread needs it
                self._lock.release()
                self.bg_transcriber_thread.join(timeout=2.0)
                self._lock.acquire()
                
            # Reset parallel transcription state
            self.transcribed_text_buffer = []
            self.last_context = "The user is dictating. Valid English text."
            self.stop_transcribing_event.clear()
            self.bg_transcriber_thread = threading.Thread(target=self._background_transcriber, daemon=True)
            self.bg_transcriber_thread.start()
            
            self.audio_queue = queue.Queue()
            
            logger.info("Playing notification sound...")
            self.play_sound()
            logger.info("Sound played.")
            
            try:
                logger.info("Calling sd.InputStream...")
                self.stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, callback=self.callback)
                logger.info("Initializing audio stream...")
                self.stream.start()
                logger.info("Audio stream started successfully.")
            except Exception as e:
                logger.error(f"Failed to start stream: {e}", exc_info=True)
                self.recording = False
                self._handle_error("Mic Error")

    def stop_recording(self, use_gemini):
        with self._lock:
            if not self.recording: 
                return
            self.recording = False
            active_stream = self.stream
            self.stream = None

        # Signal background thread to process remaining chunks and stop
        self.stop_transcribing_event.set()

        self._processing_start_time = time.time()  # Track when user released control
        logger.info(f"Stopping Recording. Gemini={use_gemini}")
        
        # Define cleanup function for background thread
        def _cleanup_stream(stream_to_close):
            if stream_to_close:
                try:
                    # Use abort() instead of stop() to prevent PortAudio deadlocks waiting for callbacks
                    stream_to_close.abort()
                    stream_to_close.close()
                    logger.info("Audio stream aborted and closed in background.")
                except Exception as e:
                    logger.error(f"Error closing stream: {e}")

        # Start cleanup in daemon thread
        threading.Thread(target=_cleanup_stream, args=(active_stream,), daemon=True).start()
        
        threading.Thread(
            target=self.transcribe_and_type, 
            args=(use_gemini,), 
            daemon=True
        ).start()

    def _background_transcriber(self):
        import re
        logger.info("Background transcriber started.")
        accumulated_audio = []
        accumulated_samples = 0
        min_samples = int(CHUNK_MIN_DURATION * SAMPLE_RATE)
        max_samples = int(CHUNK_MAX_DURATION * SAMPLE_RATE)
        
        # Keep looping until we're asked to stop AND the queue is empty AND no audio is left
        while not self.stop_transcribing_event.is_set() or not self.audio_queue.empty() or accumulated_samples > 0:
            is_boundary = False
            try:
                # Timeout allows us to re-evaluate the while loop conditions
                chunk = self.audio_queue.get(timeout=0.1)
                accumulated_audio.append(chunk)
                accumulated_samples += len(chunk)
                
                if accumulated_samples >= max_samples:
                    is_boundary = True
                elif accumulated_samples >= min_samples:
                    rms = np.sqrt(np.mean(chunk**2))
                    if rms < SILENCE_THRESHOLD:
                        is_boundary = True
            except queue.Empty:
                # If the queue is empty and we are stopping, force remaining audio to process
                if self.stop_transcribing_event.is_set() and accumulated_samples > 0:
                    is_boundary = True
                
            if is_boundary and accumulated_samples > 0:
                audio_np = np.vstack(accumulated_audio).flatten()
                
                # Pad short clips with trailing silence to ensure Whisper uses its efficient
                # execution path. Short clips (<8s) are disproportionately slow due to constant
                # FFT/attention overhead — padding amortizes this without changing the transcript.
                pad_min_samples = int(WHISPER_PAD_DURATION * SAMPLE_RATE)
                if len(audio_np) < pad_min_samples:
                    silence = np.zeros(pad_min_samples - len(audio_np), dtype=audio_np.dtype)
                    audio_np = np.concatenate([audio_np, silence])
                
                start_t = time.time()
                with self._lock:
                    model_path = self._model_dir if self._model_dir else MODEL_PATH
                    result = mlx_whisper.transcribe(
                        audio_np, 
                        path_or_hf_repo=model_path,
                        language="en",
                        initial_prompt=self.last_context
                    )
                
                duration = time.time() - start_t
                text = result["text"].strip()
                
                # Remove trailing or leading ellipses/multiple dots created by chunk boundaries
                # Also handles pure dot-chunks (e.g., "... ... ...")
                text = re.sub(r'(?:\.\s*){2,}', '', text).strip()
                
                logger.info(f"Chunk Transcribed ({accumulated_samples/SAMPLE_RATE:.1f}s audio in {duration:.2f}s): {text}")
                
                if text:
                    # Context boundary fixes: Whisper frequently capitalizes the first word of 
                    # a new chunk or ends a mid-sentence chunk with a period.
                    if self.transcribed_text_buffer:
                        prev = self.transcribed_text_buffer[-1]
                        
                        # If previous text ends with an artifact period but this chunk starts 
                        # lowercase/conjunction, strip the period.
                        if prev.endswith('.'):
                            starts_lower = text and text[0].islower()
                            
                            # List of common continuation words/phrases (lowercased for matching)
                            continuations = ('and ', 'but ', 'because ', 'or ', 'so ', 
                                             'which ', 'where ', 'who ', 'while ', 'even ', 
                                             'if ', 'then ', 'than ', 'that ', 'when ')
                            
                            is_continuation = text.lower().startswith(continuations)
                            
                            if starts_lower or is_continuation:
                                self.transcribed_text_buffer[-1] = prev[:-1].rstrip()
                                # Lowercase the incoming continuation if Whisper accidentally capped it
                                if is_continuation and text[0].isupper():
                                    text = text[0].lower() + text[1:]
                                    
                    self.transcribed_text_buffer.append(text)
                    # Keep last words for context
                    words = (self.last_context + " " + text).split()
                    self.last_context = " ".join(words[-50:])
                    
                # Reset accumulators for the next chunk
                accumulated_audio = []
                accumulated_samples = 0
                
        logger.info("Background transcriber finished.")

    def transcribe_and_type(self, use_gemini):
        try:
            logger.info("Transcribe and type worker started. Waiting for background transcriber...")
            if self.bg_transcriber_thread and self.bg_transcriber_thread.is_alive():
                self.bg_transcriber_thread.join()
            
            text = " ".join(self.transcribed_text_buffer).strip()
            logger.info(f"Final combined text: {text}")
            
            if text:
                if use_gemini:
                   logger.info("Starting Gemini processing...")
                   text = gemini.process_text(text)
                   logger.info("Gemini finished.")
                
                # Inject text FIRST (before UI update) to minimize perceived latency
                inject_start = time.time()
                self.inject_text(text)
                inject_duration = time.time() - inject_start
                if self._processing_start_time:
                    total_latency = time.time() - self._processing_start_time
                    logger.info(f"Text injected in {inject_duration*1000:.1f}ms (total {total_latency*1000:.0f}ms from key release)")
                else:
                    logger.info(f"Text injected in {inject_duration*1000:.1f}ms")
                
                # Then update UI (non-blocking)
                state_machine.set_state(AppState.SUCCESS)
                
                if self.reset_timer: 
                    self.reset_timer.cancel()
                self.reset_timer = threading.Timer(2.0, lambda: state_machine.set_state(AppState.IDLE))
                self.reset_timer.start()
            else:
                logger.info("No text transcribed.")
                state_machine.set_state(AppState.IDLE)
            

        except Exception as e:
            logger.error(f"Transcription Error: {e}", exc_info=True)
            self._handle_error("Processing Failed")


    def _handle_error(self, message):
        state_machine.set_state(AppState.ERROR, error=message)
        
        if self.reset_timer: 
            self.reset_timer.cancel()
            
        self.reset_timer = threading.Timer(3.0, lambda: state_machine.set_state(AppState.IDLE))
        self.reset_timer.start()

    def inject_text(self, text):
        from .typer import FastTyper
        from .clipboard import ClipboardManager

        # Use Clipboard Injection (Universal Strategy)
        # 1. Snapshot current clipboard
        # 2. Copy new text
        # 3. Paste
        # 4. Restore original clipboard (async)
        
        try:
            snapshot = ClipboardManager.snapshot()
            
            pyperclip.copy(text)
            # Short sleep to ensure clipboard update propagates
            time.sleep(0.05)
            
            # Simulate Cmd+V
            try:
                cmd_down = Quartz.CGEventCreateKeyboardEvent(None, 0x37, True)
                Quartz.CGEventSetFlags(cmd_down, Quartz.kCGEventFlagMaskCommand)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_down)
                
                v_down = Quartz.CGEventCreateKeyboardEvent(None, 0x09, True)
                Quartz.CGEventSetFlags(v_down, Quartz.kCGEventFlagMaskCommand)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, v_down)
                
                v_up = Quartz.CGEventCreateKeyboardEvent(None, 0x09, False)
                Quartz.CGEventSetFlags(v_up, Quartz.kCGEventFlagMaskCommand)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, v_up)

                cmd_up = Quartz.CGEventCreateKeyboardEvent(None, 0x37, False)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_up)
            except Exception:
                subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'])

            # Scheduled restoration of the user's original clipboard
            if snapshot:
                threading.Timer(0.6, lambda: ClipboardManager.restore(snapshot)).start()
                
        except Exception as e:
            logger.error(f"Injection failed: {e}", exc_info=True)

