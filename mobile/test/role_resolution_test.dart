import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/models/user_model.dart';

/// Pins the role-resolution contract that decides whether a signed-in user
/// lands in the EXPERT area or the ATHLETE area.
///
/// This must stay byte-for-byte equivalent to the website's own algorithm in
/// `frontend/pages/login/login.js` (`resolveRole`) and
/// `pages/experts/expert-dashboard.js`'s guard, because both clients read the
/// SAME `users/{uid}` document. If they ever disagree, one platform routes an
/// account differently from the other — which is precisely the class of bug
/// these tests exist to prevent.
void main() {
  UserModel user({
    String role = 'athlete',
    List<String> roles = const [],
    String expertStatus = 'none',
  }) =>
      UserModel(
        uid: 'u1',
        email: 'a@b.c',
        role: role,
        roles: roles,
        expertStatus: expertStatus,
      );

  group('resolves EXPERT', () {
    test('legacy single role field', () {
      expect(user(role: 'expert').resolvedRole, 'expert');
    });
    test('roles contains expert', () {
      expect(user(roles: ['expert']).resolvedRole, 'expert');
    });
    test('roles contains expert_pending — an application under review is still '
        'the expert experience, not the athlete one', () {
      expect(user(roles: ['expert_pending']).resolvedRole, 'expert');
    });
    test('expert_status approved', () {
      expect(user(expertStatus: 'approved').resolvedRole, 'expert');
    });
    test('expert_status pending', () {
      expect(user(expertStatus: 'pending').resolvedRole, 'expert');
    });

    test('roles contains BOTH athlete and expert_pending — the exact shape the '
        'website Google role-picker writes', () {
      // login.js writes newRoles = ['athlete'] + ['expert_pending'] when the
      // user picks Expert. Any implementation that looked at roles.first, or
      // asked "does it contain athlete?", would mis-route this real account to
      // the athlete area.
      final u = user(roles: ['athlete', 'expert_pending']);
      expect(u.isExpert, isTrue);
      expect(u.resolvedRole, 'expert');
    });

    test('expert markers win even when the legacy role still says athlete', () {
      expect(user(role: 'athlete', expertStatus: 'approved').resolvedRole, 'expert');
      expect(user(role: 'athlete', roles: ['expert']).resolvedRole, 'expert');
    });
  });

  group('resolves ATHLETE', () {
    test('a plain athlete', () {
      expect(user().resolvedRole, 'athlete');
      expect(user().isExpert, isFalse);
    });
    test('roles contains only athlete', () {
      expect(user(roles: ['athlete']).resolvedRole, 'athlete');
    });
    test('expert_status none / rejected is NOT an expert', () {
      expect(user(expertStatus: 'none').resolvedRole, 'athlete');
      expect(user(expertStatus: 'rejected').resolvedRole, 'athlete');
    });
  });

  group('fromMap — tolerant of real Firestore documents', () {
    test('a document with no role fields at all defaults to athlete, not a crash', () {
      final u = UserModel.fromMap({'uid': 'u1', 'email': 'a@b.c'});
      expect(u.resolvedRole, 'athlete');
    });
    test('reads all three role fields off the document', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'email': 'a@b.c',
        'role': 'athlete',
        'roles': ['athlete', 'expert_pending'],
        'expert_status': 'pending',
      });
      expect(u.roles, ['athlete', 'expert_pending']);
      expect(u.expertStatus, 'pending');
      expect(u.resolvedRole, 'expert');
    });
    test('an expert document round-trips through toMap/fromMap', () {
      final original = user(role: 'expert', roles: ['expert'], expertStatus: 'approved');
      final restored = UserModel.fromMap({...original.toMap(), 'uid': 'u1'});
      expect(restored.resolvedRole, 'expert');
    });
  });
}
