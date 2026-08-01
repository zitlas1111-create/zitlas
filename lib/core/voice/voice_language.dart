import 'package:flutter/foundation.dart';

/// The languages Zino can speak. Must stay in lockstep with
/// `backend/services/voice_service.py`'s `SUPPORTED_LANGUAGES` — the wire
/// value is [id], and the backend normalizes anything unknown to Hinglish.
enum VoiceLanguage {
  english('english', '🇬🇧', 'English', 'en-US', false),
  hindi('hindi', '🇮🇳', 'Hindi', 'hi-IN', false),

  /// The recommended default for ZITLAS's audience: Hindi grammar in Roman
  /// script, freely mixed with English fitness vocabulary — how Indian
  /// athletes actually talk ("aaj ka workout easy hai, bas 20 minute").
  hinglish('hinglish', '⭐', 'Hinglish', 'hi-IN', true);

  const VoiceLanguage(this.id, this.flag, this.label, this.localeId, this.recommended);

  /// Wire value sent to the backend.
  final String id;
  final String flag;
  final String label;

  /// BCP-47 tag for the DEVICE speech engine (the fallback voice) — the
  /// backend picks its own hint for ElevenLabs/Whisper independently.
  final String localeId;

  final bool recommended;

  static const fallback = VoiceLanguage.hinglish;

  /// Parses a stored/remote value. Anything unrecognised becomes the
  /// recommended default rather than throwing — a bad profile value must
  /// never break the call screen.
  static VoiceLanguage fromId(String? id) {
    final needle = (id ?? '').trim().toLowerCase();
    for (final v in VoiceLanguage.values) {
      if (v.id == needle) return v;
    }
    return fallback;
  }
}

/// A resolved reply from the voice backend.
@immutable
class VoiceReply {
  const VoiceReply({
    required this.text,
    required this.language,
    this.audio,
    this.voiceError,
  });

  final String text;
  final VoiceLanguage language;

  /// MP3 bytes from ElevenLabs, or null when synthesis was unavailable.
  /// Null is NOT a failure of the turn — [text] is still a real answer, and
  /// the caller falls back to the device voice.
  final Uint8List? audio;

  /// Why synthesis was unavailable, for debug logs only.
  final String? voiceError;

  bool get hasAudio => audio != null && audio!.isNotEmpty;
}
