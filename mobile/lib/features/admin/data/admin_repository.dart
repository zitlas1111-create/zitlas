import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/network/api_client.dart';

/// One pending `expert_certificates` doc as the admin console needs it —
/// carries the `expertId`/`expertName` the expert-side [ExpertCertificate]
/// model omits, since the admin reviews certs ACROSS experts.
class AdminCert {
  const AdminCert({
    required this.certId,
    required this.expertId,
    this.expertName,
    this.certificateName,
    this.issuingOrganization,
    this.certificateUrl,
    this.verificationScore,
    this.uploadedAt,
  });

  final String certId;
  final String expertId;
  final String? expertName;
  final String? certificateName;
  final String? issuingOrganization;
  final String? certificateUrl;
  final num? verificationScore;
  final DateTime? uploadedAt;

  factory AdminCert.fromDoc(String id, Map<String, dynamic> m) {
    DateTime? uploaded;
    final u = m['uploadedAt'];
    if (u is Timestamp) {
      uploaded = u.toDate();
    } else if (u is String) {
      uploaded = DateTime.tryParse(u);
    }
    num? score;
    final s = m['verificationScore'];
    if (s is num) {
      score = s;
    } else if (s is String) {
      score = num.tryParse(s);
    }
    return AdminCert(
      certId: id,
      expertId: (m['expertId'] ?? '').toString(),
      expertName: m['expertName'] as String?,
      certificateName: m['certificateName'] as String?,
      issuingOrganization: m['issuingOrganization'] as String?,
      certificateUrl: m['certificateUrl'] as String?,
      verificationScore: score,
      uploadedAt: uploaded,
    );
  }
}

/// Admin console data access — the native equivalent of the website's
/// `pages/admin/admin-review.js` + `assets/js/certificate-manager.js` admin
/// path. Reads the SAME `expert_certificates` collection and calls the SAME
/// `/api/admin/*` endpoints; no new API, no new collection, no client-side
/// verification logic (the backend owns `verificationStatus`,
/// `experts/{uid}.verification`, and the `expert` custom claim — Admin SDK).
class AdminRepository {
  AdminRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    ApiClient? apiClient,
  })  : _db = firestore,
        // ignore: prefer_initializing_formals
        _auth = auth,
        _api = apiClient ?? ApiClient() {
    _api.authTokenProvider = () async => _auth.currentUser?.getIdToken();
  }

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;

  /// True only when the signed-in user carries the backend-set `admin` custom
  /// claim (`identity_service.grant_admin` / `ZITLAS_ADMIN_UIDS`). Mirrors
  /// `admin-review.js`'s claim-ONLY gate — never the client-writable
  /// `users.role`, which a client could forge.
  Future<bool> isAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final res = await user.getIdTokenResult();
    return res.claims?['admin'] == true;
  }

  /// Live pending-review certificates across every expert
  /// (`certificate-manager.js listenForPendingCertificates`), oldest first.
  /// `firestore.rules` gates this read on the admin claim.
  Stream<List<AdminCert>> watchPendingCertificates() {
    return _db
        .collection('expert_certificates')
        .where('verificationStatus', isEqualTo: 'pending_review')
        .snapshots()
        .map((snap) => snap.docs.map((d) => AdminCert.fromDoc(d.id, d.data())).toList()
          ..sort((a, b) => (a.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0))));
  }

  /// `POST /api/admin/certificates/approve` — backend sets
  /// `verificationStatus='verified'`, recomputes `experts/{uid}.verification`,
  /// and grants the expert claim (all Admin SDK, bypassing rules).
  Future<void> approve(String certId) =>
      _api.post('/api/admin/certificates/approve', body: {'certId': certId});

  /// `POST /api/admin/certificates/reject` — records the reason + recomputes.
  Future<void> reject(String certId, String reason) =>
      _api.post('/api/admin/certificates/reject', body: {'certId': certId, 'reason': reason});
}
