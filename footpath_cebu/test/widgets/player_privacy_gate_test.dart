import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';

const _first = Player(
  id: 'p1',
  name: 'First Player',
  age: 14,
  classYear: 'Class of 2028',
  ageTier: AgeTier.development,
  eligibility: EligibilityStatus.eligible,
  ratings: PlayerRatings(
    pace: 1,
    shooting: 1,
    passing: 1,
    dribbling: 1,
    defending: 1,
    physical: 1,
  ),
);

const _second = Player(
  id: 'p2',
  name: 'Second Player',
  age: 15,
  classYear: 'Class of 2027',
  ageTier: AgeTier.development,
  eligibility: EligibilityStatus.eligible,
  ratings: PlayerRatings(
    pace: 1,
    shooting: 1,
    passing: 1,
    dribbling: 1,
    defending: 1,
    physical: 1,
  ),
);

class _PinRepo implements PlayerPrivacyPinRepository {
  @override
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId) async =>
      const PlayerPrivacyPinStatus(hasPin: true, locked: false);

  @override
  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  }) => fetchStatus(playerId);

  @override
  Future<String> verifyPin(String playerId, String pin) async =>
      'test-unlock-token';

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) =>
      fetchStatus(playerId);
}

class _SetupPinRepo implements PlayerPrivacyPinRepository {
  @override
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId) async =>
      const PlayerPrivacyPinStatus(hasPin: false, locked: false);

  @override
  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  }) async => const PlayerPrivacyPinStatus(
    hasPin: true,
    locked: false,
    unlockToken: 'new-pin-unlock-token',
  );

  @override
  Future<String> verifyPin(String playerId, String pin) async =>
      'test-unlock-token';

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) async =>
      const PlayerPrivacyPinStatus(hasPin: false, locked: false);
}

class _Switcher extends StatefulWidget {
  const _Switcher();

  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  var _player = _first;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => _player = _second),
          child: const Text('switch'),
        ),
        Expanded(
          child: PlayerPrivacyGate(
            player: _player,
            isGuardian: true,
            child: Text(_player.name),
          ),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('switching players clears the entered privacy PIN', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerPrivacyPinRepositoryProvider.overrideWithValue(_PinRepo()),
        ],
        child: const MaterialApp(home: Scaffold(body: _Switcher())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset PIN in Player privacy PIN'), findsOneWidget);
    await tester.tap(find.text('Reset PIN in Player privacy PIN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Manage First Player'), findsOneWidget);
    Navigator.of(
      tester.element(find.textContaining('Manage First Player')),
    ).pop();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  for (final size in <Size>[const Size(360, 640), const Size(800, 1180)]) {
    testWidgets('first-time PIN setup fits ${size.width.toInt()}px layout', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerPrivacyPinRepositoryProvider.overrideWithValue(
              _SetupPinRepo(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerPrivacyGate(
                player: _first,
                requirePinSetup: true,
                child: Text('Private dashboard'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your privacy PIN'), findsOneWidget);
      expect(find.text('Choose your PIN'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      final cardWidth = tester.getSize(find.byType(Card)).width;
      final expectedGutter = size.width >= 600 ? 64 : 32;
      expect(cardWidth, lessThanOrEqualTo(size.width - expectedGutter));
    });
  }

  testWidgets('first-time PIN setup validates and completes the flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerPrivacyPinRepositoryProvider.overrideWithValue(_SetupPinRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PlayerPrivacyGate(
              player: _first,
              requirePinSetup: true,
              child: Text('Private dashboard'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12');
    await tester.enterText(fields.at(1), '12');
    await tester.ensureVisible(find.text('Create PIN and continue'));
    await tester.tap(find.text('Create PIN and continue'));
    await tester.pump();
    expect(find.text('PIN must contain 4 to 6 digits.'), findsOneWidget);

    await tester.enterText(fields.at(0), '1234');
    await tester.enterText(fields.at(1), '4321');
    await tester.ensureVisible(find.text('Create PIN and continue'));
    await tester.tap(find.text('Create PIN and continue'));
    await tester.pump();
    expect(
      find.text('PINs do not match. Try entering them again.'),
      findsOneWidget,
    );

    await tester.enterText(fields.at(1), '1234');
    await tester.ensureVisible(find.text('Create PIN and continue'));
    await tester.tap(find.text('Create PIN and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Private dashboard'), findsOneWidget);
  });
}
