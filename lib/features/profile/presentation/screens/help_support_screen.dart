import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../data/profile_repository.dart';

const _categories = [
  'Technical Issue',
  'Training Plan Issue',
  'Nutrition Plan Issue',
  'Account Problem',
  'Subscription',
  'Feature Request',
  'Other',
];

/// Native rebuild of `frontend/pages/profile/help-support/help-support.html`
/// + `.js` — Contact Support. Same fields, same validation rules (message
/// min 20 chars), submitting to the real `POST /api/support/contact`
/// endpoint. The screenshot attachment is collected in the UI but never
/// actually transmitted on the website either — faithfully not sent here.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>().profile;
    return _HelpSupportBody(
      prefillName: auth?.name ?? '',
      prefillEmail: auth?.email ?? '',
      repository: ProfileRepository(firestore: FirebaseFirestore.instance, auth: FirebaseAuth.instance),
    );
  }
}

class _HelpSupportBody extends StatefulWidget {
  const _HelpSupportBody({required this.prefillName, required this.prefillEmail, required this.repository});
  final String prefillName;
  final String prefillEmail;
  final ProfileRepository repository;

  @override
  State<_HelpSupportBody> createState() => _HelpSupportBodyState();
}

class _HelpSupportBodyState extends State<_HelpSupportBody> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String? _category;
  bool _sending = false;

  String? _nameErr, _emailErr, _subjectErr, _categoryErr, _messageErr;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.prefillName;
    _emailCtrl.text = widget.prefillEmail;
    _messageCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _nameErr = _nameCtrl.text.trim().isEmpty ? 'Full name is required.' : null;
      final email = _emailCtrl.text.trim();
      _emailErr = email.isEmpty
          ? 'Email is required.'
          : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
              ? 'Enter a valid email address.'
              : null;
      _subjectErr = _subjectCtrl.text.trim().isEmpty ? 'Subject is required.' : null;
      _categoryErr = (_category == null || _category!.isEmpty) ? 'Please select a category.' : null;
      final msg = _messageCtrl.text.trim();
      _messageErr = msg.isEmpty ? 'Message is required.' : (msg.length < 20 ? 'Message must be at least 20 characters.' : null);
    });
    return _nameErr == null && _emailErr == null && _subjectErr == null && _categoryErr == null && _messageErr == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _sending = true);
    try {
      await widget.repository.submitSupportRequest(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        category: _category!,
        message: _messageCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your message has been sent to Team ZITLAS.')));
      _subjectCtrl.clear();
      _messageCtrl.clear();
      setState(() => _category = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _messageCtrl.text.length;
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: ZitlasTokens.textPrimary), onPressed: () => context.pop()),
        title: const Text('Help & Support', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: ZitlasTokens.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.help_outline_rounded, size: 26, color: ZitlasTokens.primaryDark),
                  ),
                  const SizedBox(height: 10),
                  const Text('Help & Support', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('Need help? Send your query directly to Team ZITLAS.', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary), textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _field('Full Name', required: true, error: _nameErr, child: TextField(controller: _nameCtrl, decoration: _decoration('Enter your full name'))),
            _field('Email', required: true, error: _emailErr, child: TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _decoration('your@email.com'))),
            _field('Subject', required: true, error: _subjectErr, child: TextField(controller: _subjectCtrl, decoration: _decoration('Brief subject of your query'))),
            _field(
              'Category',
              required: true,
              error: _categoryErr,
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: _decoration('Select a category'),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            _field(
              'Message',
              required: true,
              error: _messageErr,
              child: TextField(controller: _messageCtrl, maxLines: 5, decoration: _decoration('Describe your issue or query in detail...')),
              footer: Text(
                '$charCount characters (min. 20)',
                style: TextStyle(fontSize: 11, color: charCount >= 20 ? ZitlasTokens.success : (charCount > 0 ? ZitlasTokens.primaryDark : ZitlasTokens.textMuted)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: ZitlasTokens.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 17, color: Colors.white),
                label: Text(_sending ? 'Sending…' : 'Send Message', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                onPressed: _sending ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, {required Widget child, bool required = false, String? error, Widget? footer}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RichText(
              text: TextSpan(
                text: label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ZitlasTokens.textSecondary),
                children: required ? const [TextSpan(text: ' *', style: TextStyle(color: ZitlasTokens.danger))] : null,
              ),
            ),
          ),
          child,
          if (footer != null) Padding(padding: const EdgeInsets.only(top: 4), child: footer),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(error, style: const TextStyle(fontSize: 11, color: ZitlasTokens.danger))),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: ZitlasTokens.textMuted, fontSize: 13.5),
      filled: true,
      fillColor: ZitlasTokens.bgCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ZitlasTokens.borderSub)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ZitlasTokens.borderSub)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ZitlasTokens.primary)),
    );
  }
}
