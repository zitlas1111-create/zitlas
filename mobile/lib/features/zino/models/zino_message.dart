import 'package:flutter/foundation.dart';

/// One turn in a Zino conversation.
///
/// Matches the `[{role:'user'|'zino', text}]` shape the backend expects
/// (`ZinoChatRequest.history`), plus local-only fields the UI needs for
/// failed/retryable turns.
@immutable
class ZinoMessage {
  const ZinoMessage({
    required this.text,
    required this.isUser,
    required this.at,
    this.failed = false,
  });

  final String text;
  final bool isUser;
  final DateTime at;

  /// A user turn whose reply never arrived. Kept in the thread (rather than
  /// silently dropped) so the athlete can see what they said and retry it.
  final bool failed;

  ZinoMessage copyWith({bool? failed}) =>
      ZinoMessage(text: text, isUser: isUser, at: at, failed: failed ?? this.failed);

  Map<String, dynamic> toMap() => {
        'text': text,
        'isUser': isUser,
        'at': at.toIso8601String(),
      };

  static ZinoMessage? fromMap(Map<String, dynamic> map) {
    final text = map['text'];
    if (text is! String) return null;
    return ZinoMessage(
      text: text,
      isUser: map['isUser'] == true,
      at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// A quick-action chip. Ported verbatim from `zino.js`'s `CHIPS` — same
/// icons, same labels, same underlying questions, so the two clients prompt
/// Zino identically.
@immutable
class ZinoChip {
  const ZinoChip(this.icon, this.label, this.question);
  final String icon;
  final String label;
  final String question;
}

const kZinoChips = <ZinoChip>[
  ZinoChip('🍽', "Explain Today's Diet",
      "Can you explain today's diet plan and why it's set up this way?"),
  ZinoChip('🏋', 'Explain Workout', "Can you explain today's workout?"),
  ZinoChip('📊', 'My Progress', 'Summarize my progress so far.'),
  ZinoChip('💧', 'Water Target', "What's my water target for today?"),
  ZinoChip('😴', 'Sleep Tips', 'Any tips to help me sleep better?'),
  ZinoChip('🤒', "I'm Sick Today", "I'm not feeling well today, what should I do?"),
  ZinoChip('👨‍⚕️', 'Ask My Coach', 'How do I ask my Personal Coach a question?'),
  ZinoChip('📅', 'Weekly Summary', 'Give me a summary of my week.'),
  ZinoChip('🔥', 'Motivate Me', 'I need some motivation today.'),
];
