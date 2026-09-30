import 'package:flutter/material.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_member_registration_flow.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_player_registration_flow.dart';

class CoordinatorCreateAccountScreen extends StatefulWidget {
  const CoordinatorCreateAccountScreen({super.key});

  /// Creates the mutable state used by this view.
  @override
  State<CoordinatorCreateAccountScreen> createState() =>
      _CoordinatorCreateAccountScreenState();
}

class _CoordinatorCreateAccountScreenState
    extends State<CoordinatorCreateAccountScreen> {
  String _type = 'Player';
  bool _creatingGuardianForPlayer = false;
  MemberRegistrationResult? _createdGuardian;

  /// Switches which type of account the coordinator is creating.
  void _changeType(String type) {
    setState(() {
      _type = type;
      _creatingGuardianForPlayer = false;
      _createdGuardian = null;
    });
  }

  /// Starts guardian account creation before registering a linked player.
  void _startGuardianForPlayer() {
    setState(() {
      _type = 'Guardian';
      _creatingGuardianForPlayer = true;
      _createdGuardian = null;
    });
  }

  /// Returns to the choice of how to link a guardian.
  void _returnToGuardianQuestion() {
    setState(() {
      _type = 'Player';
      _creatingGuardianForPlayer = false;
      _createdGuardian = null;
    });
  }

  /// Continues player registration using the newly created guardian account.
  void _continueWithGuardian(MemberRegistrationResult result) {
    setState(() {
      _type = 'Player';
      _creatingGuardianForPlayer = false;
      _createdGuardian = result;
    });
  }

  /// Builds the coordinator create account screen view.
  @override
  Widget build(BuildContext context) {
    if (_type == 'Player') {
      return CoordinatorPlayerRegistrationFlow(
        onAccountTypeChanged: _changeType,
        onCreateGuardianRequested: _startGuardianForPlayer,
        createdGuardian: _createdGuardian,
      );
    }
    return CoordinatorMemberRegistrationFlow(
      role: _type == 'Coach'
          ? MemberAccountRole.coach
          : MemberAccountRole.guardian,
      onAccountTypeChanged: _changeType,
      purpose: _creatingGuardianForPlayer
          ? MemberRegistrationPurpose.playerRegistration
          : MemberRegistrationPurpose.standalone,
      onBack: _creatingGuardianForPlayer ? _returnToGuardianQuestion : null,
      onCreated: _creatingGuardianForPlayer ? _continueWithGuardian : null,
    );
  }
}
