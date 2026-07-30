import '../../../core/util/json_coerce.dart';

/// `users/{uid}.personalInfo` — mirrors `zitlas_personal_info` exactly
/// (`personal-info.js`'s `loadFormData()`/save handler). Every field is
/// optional except `fullName`, which the website itself requires
/// (`validate()`) — everything else may be absent on a legacy/incomplete
/// profile and must not crash the app.
class PersonalInfo {
  const PersonalInfo({
    this.photo,
    this.fullName,
    this.email,
    this.mobile,
    this.dob,
    this.gender,
    this.city,
    this.state,
    this.heightCm,
    this.weightKg,
    this.preferredHeightUnit = 'cm',
    this.preferredWeightUnit = 'kg',
  });

  final String? photo;
  final String? fullName;
  final String? email;
  final String? mobile;

  /// ISO date string (`yyyy-MM-dd`), matching `<input type="date">`.
  final String? dob;

  /// `'male' | 'female' | 'other' | 'prefer-not'`
  final String? gender;
  final String? city;
  final String? state;
  final num? heightCm;
  final num? weightKg;

  /// `'cm' | 'ftin'`
  final String preferredHeightUnit;

  /// `'kg' | 'lbs'`
  final String preferredWeightUnit;

  /// `computeAge(dobValue)` (personal-info.js:122-131) — same-day-of-month
  /// boundary handling, ported exactly.
  int? get age {
    final d = dob;
    if (d == null || d.isEmpty) return null;
    final birth = DateTime.tryParse(d);
    if (birth == null) return null;
    final today = DateTime.now();
    var age = today.year - birth.year;
    final m = today.month - birth.month;
    if (m < 0 || (m == 0 && today.day < birth.day)) age--;
    return age >= 0 ? age : null;
  }

  factory PersonalInfo.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PersonalInfo();
    return PersonalInfo(
      photo: asText(m['photo']),
      fullName: asText(m['fullName']),
      email: asText(m['email']),
      mobile: asText(m['mobile']),
      dob: asText(m['dob']),
      gender: asText(m['gender']),
      city: asText(m['city']),
      state: asText(m['state']),
      heightCm: asNum(m['height_cm']),
      weightKg: asNum(m['weight_kg']),
      preferredHeightUnit: asText(m['preferred_height_unit']) ?? 'cm',
      preferredWeightUnit: asText(m['preferred_weight_unit']) ?? 'kg',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (photo != null) 'photo': photo,
      'fullName': fullName ?? '',
      'email': email ?? '',
      'mobile': mobile ?? '',
      'dob': dob ?? '',
      'age': age?.toString() ?? '',
      'gender': gender ?? '',
      'city': city ?? '',
      'state': state ?? '',
      'preferred_height_unit': preferredHeightUnit,
      'preferred_weight_unit': preferredWeightUnit,
      if (heightCm != null) 'height_cm': heightCm,
      if (weightKg != null) 'weight_kg': weightKg,
    };
  }

  PersonalInfo copyWith({
    String? photo,
    String? fullName,
    String? email,
    String? mobile,
    String? dob,
    String? gender,
    String? city,
    String? state,
    num? heightCm,
    num? weightKg,
    String? preferredHeightUnit,
    String? preferredWeightUnit,
  }) {
    return PersonalInfo(
      photo: photo ?? this.photo,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      city: city ?? this.city,
      state: state ?? this.state,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      preferredHeightUnit: preferredHeightUnit ?? this.preferredHeightUnit,
      preferredWeightUnit: preferredWeightUnit ?? this.preferredWeightUnit,
    );
  }
}

/// `ZitlasMembership.getMembership()` (membership.js:50-68) — the same
/// expiry-degradation rule ported exactly: an expired premium term reads
/// back as basic, driven only by the backend-written `premium_expiry_date`,
/// never a client-set flag.
class Membership {
  const Membership({
    this.plan = 'basic',
    this.billing = 'monthly',
    this.premiumExpiryDate,
  });

  /// `'basic' | 'premium'` — already degraded past expiry, see [fromMap].
  final String plan;

  /// `'monthly' | 'yearly'`
  final String billing;
  final DateTime? premiumExpiryDate;

  bool get isPremium => plan == 'premium';

  factory Membership.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const Membership();
    final plan = asText(m['plan']) ?? 'basic';
    final billing = asText(m['billing']) ?? 'monthly';
    final expiryRaw = asText(m['premium_expiry_date']);
    final expiry = expiryRaw != null ? DateTime.tryParse(expiryRaw) : null;

    if (plan == 'premium' && expiry != null && !expiry.isAfter(DateTime.now())) {
      return Membership(plan: 'basic', billing: billing, premiumExpiryDate: expiry);
    }
    return Membership(plan: plan, billing: billing, premiumExpiryDate: expiry);
  }
}
