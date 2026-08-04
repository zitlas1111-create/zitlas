import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../../expert_dashboard/models/expert_models.dart';
import '../../../experts/data/experts_repository.dart';

/// Native rebuild of the athlete-facing side of `cprofile.js`'s
/// `openChatOverlay()`/`renderConversationMessages()` — replacing the
/// Phase-1 placeholder. Text-only; image attachments and WebRTC voice
/// calling are deferred (same precedent as the Expert Dashboard phase — no
/// phone-dialer alternative exists in production, only unbuilt WebRTC).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.roomId, this.expertId, this.expertName});

  final String roomId;
  final String? expertId;
  final String? expertName;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthState>().profile;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repo = ExpertsRepository(firestore: FirebaseFirestore.instance, auth: FirebaseAuth.instance);
    return _ChatBody(
      repository: repo,
      roomId: roomId,
      athleteId: profile.uid,
      athleteName: profile.name ?? 'Athlete',
      expertId: expertId,
      expertName: expertName,
    );
  }
}

class _ChatBody extends StatefulWidget {
  const _ChatBody({
    required this.repository,
    required this.roomId,
    required this.athleteId,
    required this.athleteName,
    this.expertId,
    this.expertName,
  });

  final ExpertsRepository repository;
  final String roomId;
  final String athleteId;
  final String athleteName;
  final String? expertId;
  final String? expertName;

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  /// Live coaching status for THIS pair, or null while it loads / when this
  /// thread isn't a coaching one at all.
  ///
  /// History always stays readable — an athlete's conversation with a former
  /// coach is theirs. Only the composer closes.
  StreamSubscription<CoachingRelationship?>? _relSub;
  CoachingRelationship? _relationship;
  bool _relLoaded = false;

  @override
  void initState() {
    super.initState();
    _relSub = ExpertsRepository(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
    ).watchMyCoachingRelationship(widget.athleteId).listen(
      (rel) {
        if (!mounted) return;
        setState(() {
          _relationship = rel;
          _relLoaded = true;
        });
      },
      onError: (_) {
        // Unreadable status must not lock a working chat — fail OPEN here.
        // The Firestore rule on chat_rooms is the real gate; this is UI.
        if (mounted) setState(() => _relLoaded = true);
      },
    );
  }

  /// True when this thread is with a coach whose relationship has ENDED.
  ///
  /// Deliberately narrow: only when we have loaded a relationship, it names
  /// THIS expert, and it is no longer active. An ordinary expert chat (a plan
  /// review, say) is never locked by this.
  bool get _coachingEnded {
    if (!_relLoaded) return false;
    final rel = _relationship;
    if (rel == null) return false;
    if (widget.expertId == null || rel.coachId != widget.expertId) return false;
    return !rel.isActive;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _relSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: ZitlasTokens.textPrimary), onPressed: () => context.pop()),
        title: StreamBuilder<ChatRoom?>(
          stream: widget.repository.watchChatRoom(widget.roomId),
          builder: (context, snap) {
            final name = snap.data?.expertName ?? widget.expertName ?? 'Expert';
            return Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary));
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: widget.repository.watchMessages(widget.roomId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: ZitlasTokens.primary));
                  }
                  final messages = snap.data!;
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text('Say hello to start the conversation.', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textMuted)),
                    );
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  });
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _MessageBubble(message: messages[i]),
                  );
                },
              ),
            ),
            if (_coachingEnded)
              const _CoachingEndedBar()
            else
              _InputBar(
                controller: _controller,
                sending: _sending,
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final expertId = widget.expertId;
    if (expertId == null) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await widget.repository.sendMessage(
        chatId: widget.roomId,
        expertId: expertId,
        expertName: widget.expertName ?? 'Expert',
        athleteId: widget.athleteId,
        athleteName: widget.athleteName,
        text: text,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.senderType == 'athlete';
    if (message.isSystem) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(message.text, style: const TextStyle(fontSize: 11, color: ZitlasTokens.textMuted)),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? ZitlasTokens.primary : ZitlasTokens.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(fontSize: 13.5, color: mine ? Colors.white : ZitlasTokens.textPrimary),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.sending, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: ZitlasTokens.bgCard, border: Border(top: BorderSide(color: ZitlasTokens.borderSub))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Type a message…',
                filled: true,
                fillColor: ZitlasTokens.bgCardLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: ZitlasTokens.primary),
          ),
        ],
      ),
    );
  }
}


/// Replaces the composer once coaching has ended.
///
/// The conversation above stays exactly where it was — nothing is hidden or
/// deleted. This only says why there is no longer a place to type.
class _CoachingEndedBar extends StatelessWidget {
  const _CoachingEndedBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: const BoxDecoration(
        color: ZitlasTokens.bgCard,
        border: Border(top: BorderSide(color: ZitlasTokens.borderSub)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Personal Coaching ended.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ZitlasTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Your conversation is kept here. Start a new coaching relationship '
            'to continue chatting.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: ZitlasTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
