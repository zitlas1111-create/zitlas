import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Microphone capture for the voice call.
///
/// Records to a temporary file (the `record` plugin's most reliable mode on
/// Android), reads it back as bytes for upload, and DELETES it immediately.
/// The athlete's speech is never left sitting in app storage after it has been
/// transcribed — it's transient input, not a recording feature.
class VoiceRecorder {
  VoiceRecorder({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  /// Whether the OS has granted microphone access. The plugin asks on first
  /// call, so this doubles as the permission request.
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] mic permission check failed: $e');
      return false;
    }
  }

  Future<bool> get isRecording async {
    try {
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  /// Begins capture. Returns false when the mic is unavailable or denied —
  /// never throws into the call screen.
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/zino_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          // AAC in an m4a container: small enough to upload quickly on mobile
          // data, and natively supported by Whisper.
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          // 16 kHz is Whisper's own working rate — recording higher just
          // uploads bytes the model discards.
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] record start failed: $e');
      _path = null;
      return false;
    }
  }

  /// Stops capture and returns the clip. Null means nothing usable was
  /// captured (cancelled, permission revoked mid-call, or an empty file).
  Future<Uint8List?> stopAndRead() async {
    try {
      final path = await _recorder.stop() ?? _path;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await _safeDelete(file);
      _path = null;
      // A file this small is silence or a mis-fire, not speech; uploading it
      // would spend a round trip to be told nothing was said.
      if (bytes.length < 1024) return null;
      return bytes;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] record stop failed: $e');
      return null;
    }
  }

  /// Aborts without returning audio — used when the athlete ends the call
  /// mid-utterance.
  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped.
    }
    final path = _path;
    _path = null;
    if (path != null) await _safeDelete(File(path));
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      // A leftover temp file in the OS cache dir is harmless and will be
      // reclaimed; failing the turn over it would not be.
      if (kDebugMode) debugPrint('[VOICE] temp cleanup failed: $e');
    }
  }

  Future<void> dispose() async {
    await cancel();
    try {
      await _recorder.dispose();
    } catch (_) {
      // Best effort during teardown.
    }
  }
}
