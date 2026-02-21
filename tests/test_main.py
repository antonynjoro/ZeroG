import unittest
from unittest.mock import MagicMock, patch
import os
import sys
import queue
import threading

# Add the project root to sys.path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import from the new package structure
from zerog.core.recorder import AudioRecorder

class TestAudioRecorder(unittest.TestCase):

    @patch('zerog.core.recorder.mlx_whisper')
    @patch('zerog.core.recorder.sd.InputStream')
    @patch('zerog.core.recorder.threading.Thread') # Mock thread starting in __init__
    def setUp(self, mock_thread, mock_sd, mock_whisper):
        # We also need to mock state_machine to avoid side effects
        with patch('zerog.core.recorder.state_machine'):
            self.recorder = AudioRecorder()

    def test_recorder_initial_state(self):
        self.assertFalse(self.recorder.recording)
        self.assertIsInstance(self.recorder.audio_queue, queue.Queue)

    @patch('zerog.core.recorder.state_machine')
    @patch('zerog.core.recorder.sd.InputStream')
    @patch('zerog.core.recorder.Cocoa.NSSound')
    def test_start_recording(self, mock_nssound, mock_sd, mock_state_machine):
        # Mock sound object
        mock_sound_instance = MagicMock()
        mock_nssound.soundNamed_.return_value = mock_sound_instance
        
        # Set state to RECORDING (required due to race condition protection)
        from zerog.core.state import AppState
        mock_state_machine.current_state = AppState.RECORDING
        
        self.recorder.start_recording()
        
        self.assertTrue(self.recorder.recording)
        
        # Verify sound played
        mock_nssound.soundNamed_.assert_called_with("Pop")
        mock_sound_instance.play.assert_called_once()
        
        mock_sd.assert_called_once()

    @patch('zerog.core.recorder.sd.InputStream')
    def test_stop_recording(self, mock_sd):
        self.recorder.recording = True
        mock_stream = MagicMock()
        self.recorder.stream = mock_stream
        
        with patch('zerog.core.recorder.threading.Thread') as mock_thread:
            self.recorder.stop_recording(use_gemini=False)
            
            self.assertFalse(self.recorder.recording)
            self.assertIsNone(self.recorder.stream)
            
            # Should spawn 2 threads: one for cleanup, one for transcription
            self.assertEqual(mock_thread.call_count, 2)
            
            # Find the cleanup thread (the one with the stream arg)
            call_args_list = mock_thread.call_args_list
            cleanup_call = None
            for call in call_args_list:
                args, kwargs = call
                if 'args' in kwargs and len(kwargs['args']) > 0 and kwargs['args'][0] == mock_stream:
                    cleanup_call = call
                    break
            
            self.assertIsNotNone(cleanup_call, "Cleanup thread not spawned")
            
            # Manually run the cleanup target to verify it closes the stream
            cleanup_target = cleanup_call[1]['target']
            cleanup_args = cleanup_call[1]['args']
            cleanup_target(*cleanup_args)
            
            mock_stream.abort.assert_called_once()
            mock_stream.close.assert_called_once()

    @patch('zerog.core.recorder.state_machine')
    @patch('zerog.core.recorder.pyperclip.copy')
    def test_transcribe_and_type_no_gemini(self, mock_copy, mock_state_machine):
        # We need to mock the local imports inside inject_text
        with patch('zerog.core.typer.FastTyper.type_text') as mock_type_text, \
             patch('zerog.core.clipboard.ClipboardManager') as mock_clipboard, \
             patch('zerog.core.recorder.Quartz') as mock_quartz:
            
            # Setup mock to return True for typing success
            mock_type_text.return_value = True
            
            # Put text directly in the buffer (simulating background transcriber)
            self.recorder.transcribed_text_buffer = ["Hello world"]
            
            # Action
            self.recorder.transcribe_and_type(use_gemini=False)
            
            # Assert
            # Should NOT use FastTyper anymore
            mock_type_text.assert_not_called()
            # Should use clipboard
            mock_clipboard.snapshot.assert_called_once()
            mock_copy.assert_called_with("Hello world")
            mock_quartz.CGEventCreateKeyboardEvent.assert_called()
    
    @patch('zerog.core.recorder.state_machine')
    @patch('zerog.core.recorder.pyperclip.copy')
    def test_transcribe_and_type_always_clipboard(self, mock_copy, mock_state_machine):
        """Test that clipboard is used regardless of text length"""
        with patch('zerog.core.typer.FastTyper.type_text') as mock_type_text, \
             patch('zerog.core.clipboard.ClipboardManager') as mock_clipboard, \
             patch('zerog.core.recorder.Quartz') as mock_quartz:
             
             # Create long text > 1000 chars
             long_text = "A" * 1005
             self.recorder.transcribed_text_buffer = [long_text]
             
             # Action
             self.recorder.transcribe_and_type(use_gemini=False)
             
             # Assert
             mock_type_text.assert_not_called()
             mock_clipboard.snapshot.assert_called_once()
             mock_copy.assert_called_with(long_text)
             mock_quartz.CGEventCreateKeyboardEvent.assert_called()
    @patch('zerog.core.recorder.state_machine')
    def test_recorder_callback(self, mock_state_machine):
        # Create a dummy audio buffer (numpy array)
        import numpy as np
        indata = np.full((1024, 1), 0.1, dtype=np.float32)
        frames = 1024
        time_info = {}
        status = None
        
        # Must be recording to process audio
        self.recorder.recording = True
        
        self.recorder.callback(indata, frames, time_info, status)
        
        # Verify queue put
        self.assertFalse(self.recorder.audio_queue.empty())
        
        # Verify broadcast
        # RMS of 0.1 is 0.1. Level = min(1.0, 0.1 * 10) = 1.0
        mock_state_machine.broadcast_audio_level.assert_called_with(1.0)
    
    @patch('zerog.core.recorder.state_machine')
    def test_silence_detection(self, mock_state_machine):
        # Mock context default
        mock_state_machine.context.get.return_value = False
        
        # 1. Start silence timer with first silent chunk
        import numpy as np
        # RMS < 0.015 (threshold) -> let's use 0.001
        # Mean of (0.001^2) = 1e-6. Sqrt(1e-6) = 0.001
        indata_silent = np.full((1024, 1), 0.001, dtype=np.float32)
        
        self.recorder.recording = True # Must be true for callback to process
        self.recorder._silence_start_time = None
        self.recorder.callback(indata_silent, 1024, {}, None)
        
        # Should have started tracking silence
        self.assertIsNotNone(self.recorder._silence_start_time)
        start_time = self.recorder._silence_start_time
        
        # 2. Advance time past SILENCE_DURATION (5.0s)
        # We need to mock time.time() to simulate time passing, 
        # but since we can't easily patch time.time inside the method after instance creation 
        # without affecting other things or using a class-level patch, 
        # we'll manually set start_time to be 11 seconds ago.
        import time
        self.recorder._silence_start_time = time.time() - 11.0
        
        # 3. Process another silent chunk
        with patch('zerog.core.recorder.threading.Thread') as mock_thread:
            self.recorder.callback(indata_silent, 1024, {}, None)
            
            # 4. Should trigger state change
            self.assertTrue(self.recorder._triggered_silence_stop)
            mock_thread.assert_called_once()
            
            # Verify it calls state_machine.set_state with PROCESSING
            target = mock_thread.call_args[1]['target']
            args = mock_thread.call_args[1]['args']
            
            # state_machine might be a Mock here, so target is likely mock_state_machine.set_state
            self.assertEqual(target, mock_state_machine.set_state)
            from zerog.core.state import AppState
            self.assertEqual(args[0], AppState.PROCESSING)

if __name__ == '__main__':
    unittest.main()


