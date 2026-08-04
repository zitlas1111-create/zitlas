import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/location/diet_region_repository.dart';
import '../../../../core/location/presentation/region_picker_sheet.dart';
import '../../../../core/theme/zitlas_tokens.dart';
import '../../../auth/auth_state.dart';
import '../../data/profile_repository.dart';
import '../../models/personal_info.dart';

const _photoSyncMaxChars = 180000; // matches PHOTO_SYNC_MAX_CHARS on web

/// Native rebuild of `frontend/pages/profile/personal-info/personal-info.html`
/// + `.js` — Edit Profile. Every field, its validation, and the unit-toggle
/// behavior mirror the website exactly. Saving writes `users/{uid}.personalInfo`
/// AND the height/weight subset into `users/{uid}.survey` (same dual write
/// as `initSaveBtn()`) — it deliberately does NOT recompute BMI/calculations;
/// the website doesn't either.
///
/// Reached via `context.push()` from a route outside the hub screen's own
/// Provider scope, so this fetches its own current `personalInfo` snapshot
/// rather than depending on an ambient `ProfileController`.
class PersonalInfoScreen extends StatelessWidget {
  const PersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>().profile;
    if (auth == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repository = ProfileRepository(firestore: FirebaseFirestore.instance, auth: FirebaseAuth.instance);
    // A one-time fetch, not a live listener — `personal-info.js`'s `boot()`
    // deliberately hydrates once before first paint and never re-renders
    // live: silently rewriting fields out from under someone mid-edit would
    // be worse than a stale value until they reopen the page.
    return FutureBuilder<Map<String, dynamic>?>(
      future: repository.watchUserDoc(auth.uid).first,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final info = PersonalInfo.fromMap((snap.data?['personalInfo'] as Map?)?.cast<String, dynamic>());
        return _PersonalInfoBody(uid: auth.uid, initial: info, repository: repository);
      },
    );
  }
}

class _PersonalInfoBody extends StatefulWidget {
  const _PersonalInfoBody({required this.uid, required this.initial, required this.repository});
  final String uid;
  final PersonalInfo initial;
  final ProfileRepository repository;

  @override
  State<_PersonalInfoBody> createState() => _PersonalInfoBodyState();
}

class _PersonalInfoBodyState extends State<_PersonalInfoBody> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _heightCmCtrl = TextEditingController();
  final _heightFtCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();
  final _weightKgCtrl = TextEditingController();
  final _weightLbsCtrl = TextEditingController();

  DateTime? _dob;
  String _gender = '';
  String? _photo;
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';
  bool _nameError = false;
  bool _emailError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameCtrl.text = i.fullName ?? '';
    _emailCtrl.text = i.email ?? '';
    _mobileCtrl.text = i.mobile ?? '';
    _cityCtrl.text = i.city ?? '';
    _stateCtrl.text = i.state ?? '';
    _gender = i.gender ?? '';
    _photo = i.photo;
    _dob = i.dob != null && i.dob!.isNotEmpty ? DateTime.tryParse(i.dob!) : null;
    _heightUnit = i.preferredHeightUnit;
    _weightUnit = i.preferredWeightUnit;
    if (i.heightCm != null) {
      _heightCmCtrl.text = i.heightCm!.round().toString();
      final ftIn = _cmToFtIn(i.heightCm!.toDouble());
      _heightFtCtrl.text = ftIn.$1.toString();
      _heightInCtrl.text = ftIn.$2.toString();
    }
    if (i.weightKg != null) {
      _weightKgCtrl.text = i.weightKg!.round().toString();
      _weightLbsCtrl.text = (i.weightKg!.toDouble() * 2.20462).round().toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _heightCmCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _weightKgCtrl.dispose();
    _weightLbsCtrl.dispose();
    super.dispose();
  }

  // ── Unit conversion — ported 1:1 from personal-info.js ──
  (int, int) _cmToFtIn(double cm) {
    final totalIn = cm / 2.54;
    var ft = (totalIn / 12).floor();
    var inches = (totalIn - ft * 12).round();
    if (inches == 12) {
      ft++;
      inches = 0;
    }
    return (ft.clamp(3, 8), inches.clamp(0, 11));
  }

  int _ftInToCm(int ft, int inches) => (ft * 30.48 + inches * 2.54).round();
  int _kgToLbs(num kg) => (kg * 2.20462).round();
  double _lbsToKg(num lbs) => (lbs * 0.45359237 * 10).round() / 10;

  int? get _age {
    final d = _dob;
    if (d == null) return null;
    final today = DateTime.now();
    var age = today.year - d.year;
    final m = today.month - d.month;
    if (m < 0 || (m == 0 && today.day < d.day)) age--;
    return age >= 0 ? age : null;
  }

  num? get _currentHeightCm {
    if (_heightUnit == 'cm') return num.tryParse(_heightCmCtrl.text.trim());
    final ft = int.tryParse(_heightFtCtrl.text.trim());
    final inches = int.tryParse(_heightInCtrl.text.trim());
    if (ft == null || inches == null) return null;
    return _ftInToCm(ft, inches);
  }

  num? get _currentWeightKg {
    if (_weightUnit == 'kg') return num.tryParse(_weightKgCtrl.text.trim());
    final lbs = num.tryParse(_weightLbsCtrl.text.trim());
    return lbs == null ? null : _lbsToKg(lbs);
  }

  void _toggleHeightUnit(String unit) {
    final curCm = _currentHeightCm;
    setState(() {
      _heightUnit = unit;
      if (curCm != null) {
        if (unit == 'cm') {
          _heightCmCtrl.text = curCm.round().toString();
        } else {
          final ftIn = _cmToFtIn(curCm.toDouble());
          _heightFtCtrl.text = ftIn.$1.toString();
          _heightInCtrl.text = ftIn.$2.toString();
        }
      }
    });
  }

  void _toggleWeightUnit(String unit) {
    final curKg = _currentWeightKg;
    setState(() {
      _weightUnit = unit;
      if (curKg != null) {
        if (unit == 'kg') {
          _weightKgCtrl.text = curKg.round().toString();
        } else {
          _weightLbsCtrl.text = _kgToLbs(curKg).toString();
        }
      }
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from Gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a Photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final b64 = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$b64';
    if (dataUrl.length > _photoSyncMaxChars) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That photo is too large — please pick a smaller image.')));
      }
      return;
    }
    setState(() => _photo = dataUrl);
  }

  bool _validate() {
    final nameOk = _nameCtrl.text.trim().isNotEmpty;
    final email = _emailCtrl.text.trim();
    final emailOk = email.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    setState(() {
      _nameError = !nameOk;
      _emailError = !emailOk;
    });
    return nameOk && emailOk;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your full name')));
      return;
    }
    setState(() => _saving = true);
    final info = PersonalInfo(
      photo: _photo,
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      dob: _dob != null ? '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}' : null,
      gender: _gender.isEmpty ? null : _gender,
      city: _cityCtrl.text.trim(),
      state: _stateCtrl.text.trim(),
      heightCm: _currentHeightCm,
      weightKg: _currentWeightKg,
      preferredHeightUnit: _heightUnit,
      preferredWeightUnit: _weightUnit,
    );
    try {
      await widget.repository.savePersonalInfo(widget.uid, info);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save — please try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZitlasTokens.bgStart,
      appBar: AppBar(
        backgroundColor: ZitlasTokens.bgCard,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: ZitlasTokens.textPrimary), onPressed: () => context.pop()),
        title: const Text('Personal Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: ZitlasTokens.primary.withValues(alpha: 0.15),
                        backgroundImage: _photoImage(),
                        child: _photoImage() == null
                            ? Text(
                                _nameCtrl.text.trim().isEmpty ? 'ZT' : _nameCtrl.text.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase(),
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ZitlasTokens.primaryDark),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(color: ZitlasTokens.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, size: 15, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap to change photo', style: TextStyle(fontSize: 11.5, color: ZitlasTokens.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeading(icon: Icons.person_outline_rounded, title: 'Basic Information'),
            const SizedBox(height: 12),
            _Field(label: 'Full Name', required: true, error: _nameError, child: TextField(controller: _nameCtrl, decoration: _decoration('Enter your full name'), onChanged: (_) => setState(() {}))),
            _Field(
              label: 'Email',
              error: _emailError,
              errorText: 'Enter a valid email address',
              child: TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _decoration('your@email.com'), onChanged: (_) => setState(() {})),
            ),
            _Field(label: 'Mobile Number', child: TextField(controller: _mobileCtrl, keyboardType: TextInputType.phone, decoration: _decoration('+91 00000 00000'))),
            Row(
              children: [
                Expanded(child: _Field(label: 'Date of Birth', child: _DobPicker(dob: _dob, onPick: (d) => setState(() => _dob = d)))),
                const SizedBox(width: 12),
                Expanded(child: _Field(label: 'Age', child: TextField(enabled: false, controller: TextEditingController(text: _age?.toString() ?? ''), decoration: _decoration('Years')))),
              ],
            ),
            _Field(
              label: 'Gender',
              child: DropdownButtonFormField<String>(
                initialValue: _gender.isEmpty ? null : _gender,
                decoration: _decoration('Select gender'),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                  DropdownMenuItem(value: 'prefer-not', child: Text('Prefer not to say')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? ''),
              ),
            ),
            Row(
              children: [
                Expanded(child: _Field(label: 'City', child: TextField(controller: _cityCtrl, decoration: _decoration('City')))),
                const SizedBox(width: 12),
                Expanded(child: _Field(label: 'State', child: TextField(controller: _stateCtrl, decoration: _decoration('State')))),
              ],
            ),
            const SizedBox(height: 16),
            _SectionHeading(icon: Icons.straighten_rounded, title: 'Body Metrics'),
            const SizedBox(height: 12),
            _MetricField(
              label: 'Height',
              unit: _heightUnit,
              units: const [('cm', 'CM'), ('ftin', 'FT / IN')],
              onUnitChange: _toggleHeightUnit,
              child: _heightUnit == 'cm'
                  ? TextField(controller: _heightCmCtrl, keyboardType: TextInputType.number, decoration: _decoration('e.g. 170'))
                  : Row(
                      children: [
                        Expanded(child: TextField(controller: _heightFtCtrl, keyboardType: TextInputType.number, decoration: _decoration('Feet (3–8)'))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _heightInCtrl, keyboardType: TextInputType.number, decoration: _decoration('Inches (0–11)'))),
                      ],
                    ),
            ),
            _MetricField(
              label: 'Weight',
              unit: _weightUnit,
              units: const [('kg', 'KG'), ('lbs', 'LBS')],
              onUnitChange: _toggleWeightUnit,
              child: TextField(
                controller: _weightUnit == 'kg' ? _weightKgCtrl : _weightLbsCtrl,
                keyboardType: TextInputType.number,
                decoration: _decoration(_weightUnit == 'kg' ? 'e.g. 70' : 'e.g. 154'),
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeading(icon: Icons.location_on_outlined, title: 'Preferred Food Region'),
            const SizedBox(height: 12),
            _PreferredRegionRow(uid: widget.uid),
          ],
        ),
      ),
    );
  }

  ImageProvider? _photoImage() {
    final p = _photo;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('data:')) {
      try {
        return MemoryImage(base64Decode(p.split(',').last));
      } catch (_) {
        return null;
      }
    }
    if (p.startsWith('http')) return NetworkImage(p);
    return null;
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: ZitlasTokens.textSecondary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ZitlasTokens.textPrimary)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.required = false, this.error = false, this.errorText = 'This field is required'});
  final String label;
  final Widget child;
  final bool required;
  final bool error;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
          if (error) Padding(padding: const EdgeInsets.only(top: 4), child: Text(errorText, style: const TextStyle(fontSize: 11, color: ZitlasTokens.danger))),
        ],
      ),
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField({required this.label, required this.unit, required this.units, required this.onUnitChange, required this.child});
  final String label;
  final String unit;
  final List<(String, String)> units;
  final ValueChanged<String> onUnitChange;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ZitlasTokens.textSecondary)),
              Container(
                decoration: BoxDecoration(color: ZitlasTokens.bgCardLight, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: units.map((u) {
                    final active = unit == u.$1;
                    return GestureDetector(
                      onTap: () => onUnitChange(u.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: active ? ZitlasTokens.primary : null, borderRadius: BorderRadius.circular(10)),
                        child: Text(u.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : ZitlasTokens.textSecondary)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _DobPicker extends StatelessWidget {
  const _DobPicker({required this.dob, required this.onPick});
  final DateTime? dob;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: dob ?? DateTime(2000, 1, 1),
          firstDate: DateTime(1920),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: ZitlasTokens.bgCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ZitlasTokens.borderSub)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ZitlasTokens.borderSub)),
        ),
        child: Text(
          dob != null ? '${dob!.year.toString().padLeft(4, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}' : 'Select date',
          style: TextStyle(fontSize: 13.5, color: dob != null ? ZitlasTokens.textPrimary : ZitlasTokens.textMuted),
        ),
      ),
    );
  }
}

/// Part M — "Preferred Food Region" with a `Change` action. Changing it only
/// affects FUTURE generation/swaps (nothing here ever regenerates the
/// current Diet), per the location-permission phase's explicit requirement.
class _PreferredRegionRow extends StatefulWidget {
  const _PreferredRegionRow({required this.uid});
  final String uid;

  @override
  State<_PreferredRegionRow> createState() => _PreferredRegionRowState();
}

class _PreferredRegionRowState extends State<_PreferredRegionRow> {
  late final _repo = DietRegionRepository(firestore: FirebaseFirestore.instance);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _repo.watch(widget.uid),
      builder: (context, snap) {
        final region = snap.data;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: ZitlasTokens.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: ZitlasTokens.borderSub)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Preferred Food Region', style: TextStyle(fontSize: 12.5, color: ZitlasTokens.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      region ?? 'Not set',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: region == null ? ZitlasTokens.textMuted : ZitlasTokens.textPrimary),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showRegionPickerSheet(context, current: region);
                  if (picked != null) await _repo.save(widget.uid, picked, source: 'manual');
                },
                child: const Text('Change', style: TextStyle(fontWeight: FontWeight.w700, color: ZitlasTokens.primaryDark)),
              ),
            ],
          ),
        );
      },
    );
  }
}
