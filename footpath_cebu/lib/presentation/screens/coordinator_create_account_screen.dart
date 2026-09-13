import 'package:flutter/material.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_member_registration_flow.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_player_registration_flow.dart';

class CoordinatorCreateAccountScreen extends StatefulWidget {
  const CoordinatorCreateAccountScreen({super.key});

  @override
  State<CoordinatorCreateAccountScreen> createState() =>
      _CoordinatorCreateAccountScreenState();
}

class _CoordinatorCreateAccountScreenState
    extends State<CoordinatorCreateAccountScreen> {
  String _type = 'Player';

  @override
  Widget build(BuildContext context) {
    void changeType(String type) => setState(() => _type = type);
    if (_type == 'Player') {
      return CoordinatorPlayerRegistrationFlow(
        onAccountTypeChanged: changeType,
      );
    }
    return CoordinatorMemberRegistrationFlow(
      role: _type == 'Coach'
          ? MemberAccountRole.coach
          : MemberAccountRole.guardian,
      onAccountTypeChanged: changeType,
    );
  }
}
