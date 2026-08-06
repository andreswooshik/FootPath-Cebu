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
  Future<void> verifyPin(String playerId, String pin) async {}

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) =>
      fetchStatus(playerId);
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

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });
}
