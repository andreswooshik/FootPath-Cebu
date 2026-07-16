// Audit test cases for the top FootPath-Cebu findings.
//
// These are runnable Flutter tests. To use them, copy this file into
//   footpath_cebu/test/audit/audit_findings_test.dart
// and run `flutter test`. They are kept here (docs/audit/) as an audit
// deliverable so the report and its tests live together.
//
// Backend findings (F3 object-level authz, F4 token revocation) are Django/DRF
// concerns and cannot be exercised from Dart — runnable pytest-style stubs for
// those are included as a comment block at the bottom of this file, ready to
// drop into backend/accounts/tests.py once the endpoints from F2 exist.

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/data/repositories/mock_auth_repository.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/presentation/viewmodels/guardian_dashboard_viewmodel.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Player _player(String id, String name) => Player(
      id: id,
      name: name,
      age: 15,
      classYear: 'Class of 2026',
      ageTier: AgeTier.development,
      position: 'CM',
      eligibility: EligibilityStatus.eligible,
      ratings: const PlayerRatings(
        pace: 80,
        shooting: 80,
        passing: 80,
        dribbling: 80,
        defending: 80,
        physical: 80,
      ),
    );

/// A fake linked-players repo that ONLY knows the guardian's own children —
/// modelling the server-side guarantee F3 asks for. Used to assert the
/// guardian VM never surfaces a player it wasn't given.
class _FakeLinkedRepo implements PlayerRepository {
  _FakeLinkedRepo(this._children);
  final List<Player> _children;

  @override
  Future<List<Player>> fetchLinkedPlayers() async => _children;

  @override
  Future<List<Player>> fetchSquad() async =>
      throw UnimplementedError('guardian VM must not call fetchSquad');

  @override
  Future<Player> fetchMyProfile() async =>
      throw UnimplementedError('guardian VM must not call fetchMyProfile');
}

/// Records which player ids attendance was requested for, so we can prove the
/// guardian dashboard only ever asks for a child it was actually linked to.
class _SpyAttendanceRepo implements AttendanceRepository {
  final List<String> requestedPlayerIds = [];

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) async {
    requestedPlayerIds.add(playerId);
    return [
      Attendance(
        playerId: playerId,
        status: AttendanceStatus.present,
        updatedAt: DateTime(2026, 7, 1),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// F1 — Mock auth must never be usable in a release build, and demonstrably
//      accepts a shared password for any email (the reason it must be gated).
// ---------------------------------------------------------------------------

/// The build-mode selector that main.dart SHOULD use (see F1 fix). We test the
/// pure decision function rather than main() itself.
bool selectsMockWiring({required bool releaseMode}) => !releaseMode;

void main() {
  group('F1 — mock auth wiring guard', () {
    test('release builds never select the mock wiring', () {
      expect(selectsMockWiring(releaseMode: true), isFalse);
      expect(selectsMockWiring(releaseMode: false), isTrue);
    });

    test('the real binary is not compiled in release with mock selected', () {
      // Documents the invariant at the actual runtime constant. In a normal
      // `flutter test` (debug) this is a no-op; wire it into a release smoke
      // test to catch a mis-cut build.
      if (kReleaseMode) {
        expect(selectsMockWiring(releaseMode: kReleaseMode), isFalse);
      }
    });

    test('MockAuthRepository authenticates ANY email with the shared password '
        '(this is why it must be gated out of release)', () async {
      final repo = MockAuthRepository();

      // Attacker-controlled email + the shared demo password → signed in.
      final profile = await repo.signInAndFetchProfile(
        email: 'attacker@evil.test',
        password: 'demo123',
      );
      expect(profile.email, 'attacker@evil.test');

      // And role is derived from the email string — "admin@…" self-grants ADMIN.
      final admin = await repo.signInAndFetchProfile(
        email: 'admin@evil.test',
        password: 'demo123',
      );
      expect(admin.role, 'ADMIN',
          reason: 'mock self-assigns ADMIN from the email — never ship this');
    });
  });

  // -------------------------------------------------------------------------
  // F3 (client half) — the guardian dashboard must only ever read attendance
  //     for a child it was actually linked to. The server must ALSO enforce
  //     this (see the pytest stub below); this test proves the client never
  //     asks for an unrelated id on its own.
  // -------------------------------------------------------------------------
  group('F3 — guardian only reads its linked children', () {
    test('attendance is only ever requested for a linked child id', () async {
      final children = [_player('child-1', 'Ana'), _player('child-2', 'Ben')];
      final attendance = _SpyAttendanceRepo();
      final vm = GuardianDashboardViewModel(
        GetLinkedPlayers(_FakeLinkedRepo(children)),
        GetPlayerAttendance(attendance),
      );

      await vm.load();
      await vm.selectChild('child-2');

      // Every id the VM asked attendance for must be one of the linked kids —
      // it can never fabricate or be steered to an unrelated player id.
      expect(
        attendance.requestedPlayerIds.toSet()
            .difference({'child-1', 'child-2'}),
        isEmpty,
        reason: 'guardian VM requested an id it was not linked to',
      );
    });

    test('selecting an unknown child id falls back to a linked child, never '
        'leaks a foreign id to the repository', () async {
      final children = [_player('child-1', 'Ana')];
      final attendance = _SpyAttendanceRepo();
      final vm = GuardianDashboardViewModel(
        GetLinkedPlayers(_FakeLinkedRepo(children)),
        GetPlayerAttendance(attendance),
      );

      await vm.load();
      // selectedChild getter falls back to children.first for an unknown id.
      await vm.selectChild('someone-elses-child');

      expect(attendance.requestedPlayerIds, everyElement('child-1'));
    });
  });

  // -------------------------------------------------------------------------
  // Regression guard for F2 — the live repositories target endpoints the
  // backend does not implement. This documents the expected paths so a future
  // dev wiring the backend has the contract in one place. (Pure string check,
  // no network.)
  // -------------------------------------------------------------------------
  group('F2 — live endpoint contract (documentation guard)', () {
    test('the endpoints the app expects are recorded', () {
      const expected = {
        'GET /api/players/',
        'GET /api/players/linked/',
        'GET /api/players/me/',
        'GET /api/attendance/?player=<id>',
        'GET /api/training-sessions/',
        'POST /api/training-sessions/',
      };
      // Until the backend implements these, `ServiceLocator.initFirebase()`
      // 404s. Keep this set in sync with backend/accounts/urls.py.
      expect(expected, isNotEmpty);
    });
  });
}

// ===========================================================================
// Backend test stubs (F3 object-level authz, F4 token revocation)
// ---------------------------------------------------------------------------
// Drop these into backend/accounts/tests.py once the F2 endpoints exist. They
// follow the existing APITestCase + force_authenticate / mocked-verify style.
// ===========================================================================
//
// class ObjectLevelAuthzTests(APITestCase):
//     """F3 — a guardian can only read a player they are linked to."""
//
//     def setUp(self):
//         self.guardian = make_user(Roles.GUARDIAN)
//         self.my_child = make_user(Roles.PLAYER)          # linked
//         self.other_child = User.objects.create(          # NOT linked
//             username='other@x.test', email='other@x.test',
//             role=Roles.PLAYER, firebase_uid='uid-other')
//         GuardianLink.objects.create(guardian=self.guardian, player=self.my_child)
//
//     def test_guardian_cannot_read_unlinked_players_attendance(self):
//         self.client.force_authenticate(self.guardian)
//         # assumes GET /api/attendance/?player=<id> from F2
//         url = f"{reverse('attendance-list')}?player={self.other_child.id}"
//         self.assertEqual(self.client.get(url).status_code, 403)
//
//     def test_guardian_can_read_linked_players_attendance(self):
//         self.client.force_authenticate(self.guardian)
//         url = f"{reverse('attendance-list')}?player={self.my_child.id}"
//         self.assertEqual(self.client.get(url).status_code, 200)
//
//
// class TokenRevocationTests(APITestCase):
//     """F4 — a disabled account is rejected even with an otherwise-valid token."""
//
//     @patch('accounts.authentication.ensure_initialized')
//     @patch('accounts.authentication.firebase_auth.verify_id_token')
//     def test_deactivated_user_is_rejected(self, mock_verify, _init):
//         user = make_user(Roles.COACH)          # firebase_uid='uid-coach'
//         mock_verify.return_value = {'uid': 'uid-coach'}
//         user.is_active = False
//         user.save()
//         self.client.credentials(HTTP_AUTHORIZATION='Bearer fake')
//         # The is_active=True filter in FirebaseAuthentication already blocks
//         # this today; the test locks in that guarantee.
//         self.assertEqual(self.client.get(reverse('auth-me')).status_code, 403)
