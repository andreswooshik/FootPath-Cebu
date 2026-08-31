import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

AssessmentFramework mockDevelopmentFramework(Player player) {
  final group = player.position?.group;
  final additions = _positionIndicators(group);
  final domains = <DevelopmentDomain>[
    _domain(
      'technical',
      'Technical',
      'Quality and adaptability when executing football actions.',
      [
        _indicator('firstTouchBallControl', 'First touch and ball control'),
        _indicator('passingReceiving', 'Passing and receiving'),
        _indicator('skillUnderPressure', 'Skill under pressure'),
        ...additions['technical'] ?? const [],
      ],
    ),
    _domain(
      'tactical',
      'Tactical / Game Intelligence',
      'Reading the game, choosing actions, and using space.',
      [
        _indicator('scanningAwareness', 'Scanning and awareness'),
        _indicator('decisionMaking', 'Decision-making'),
        _indicator('positioningSpace', 'Positioning and use of space'),
        ...additions['tactical'] ?? const [],
      ],
    ),
    _domain(
      'physical',
      'Physical / Coordinative',
      'Age-appropriate movement quality and football-specific capacity.',
      [
        _indicator('coordinationBalance', 'Coordination and balance'),
        _indicator('agilityDirection', 'Agility and change of direction'),
        _indicator('repeatEffortEndurance', 'Repeat effort and endurance'),
        ...additions['physical'] ?? const [],
      ],
    ),
    _domain(
      'mental',
      'Mental / Emotional',
      'Learning behaviour, confidence, composure, and response to challenge.',
      [
        _indicator('focusLearning', 'Focus and learning'),
        _indicator('confidenceCreativity', 'Confidence and creativity'),
        _indicator(
          'resilienceEmotionalControl',
          'Resilience and emotional control',
        ),
        ...additions['mental'] ?? const [],
      ],
    ),
    _domain(
      'socialValues',
      'Social / Values',
      'Humility, effort, ambition, respect, and teamwork in action.',
      [
        _indicator('humility', 'Humility'),
        _indicator('effortCommitment', 'Effort and commitment'),
        _indicator('ambition', 'Ambition'),
        _indicator('respect', 'Respect'),
        _indicator('teamwork', 'Teamwork'),
      ],
    ),
  ];
  return AssessmentFramework(
    version: 1,
    name: 'FootPath Development Framework',
    methodology: 'FIFA-aligned, Barça-inspired holistic player development.',
    disclaimer:
        'A FootPath framework; not an official FIFA or FC Barcelona assessment tool.',
    ageTier: player.ageTier.wire,
    position: player.position?.wire ?? '',
    positionGroup: switch (group) {
      PositionGroup.goalkeeper => 'GOALKEEPER',
      PositionGroup.defence => 'DEFENCE',
      PositionGroup.midfield => 'MIDFIELD',
      PositionGroup.attack => 'ATTACK',
      null => null,
    },
    scale: const [
      DevelopmentScaleOption(
        value: 1,
        label: 'Emerging',
        description: 'Needs frequent support.',
      ),
      DevelopmentScaleOption(
        value: 2,
        label: 'Developing',
        description: 'Sometimes demonstrated with support.',
      ),
      DevelopmentScaleOption(
        value: 3,
        label: 'Consistent',
        description: 'Reliably demonstrated in typical situations.',
      ),
      DevelopmentScaleOption(
        value: 4,
        label: 'Advanced',
        description: 'Reliably demonstrated under pressure.',
      ),
      DevelopmentScaleOption(
        value: 5,
        label: 'Leading',
        description: 'Excels under pressure and models the behaviour.',
      ),
      DevelopmentScaleOption(
        value: null,
        label: 'Not observed',
        description: 'Not enough recent evidence.',
      ),
    ],
    domains: domains,
  );
}

DevelopmentDomain _domain(
  String key,
  String label,
  String description,
  List<DevelopmentIndicator> indicators,
) => DevelopmentDomain(
  key: key,
  label: label,
  description: description,
  guidance: 'Judge observable, age-appropriate behaviours in recent football.',
  minimumObserved: (indicators.length + 1) ~/ 2,
  indicators: indicators,
);

DevelopmentIndicator _indicator(
  String key,
  String label, {
  bool position = false,
}) => DevelopmentIndicator(
  key: key,
  label: label,
  description: 'Use recent training and match evidence.',
  scope: position ? 'POSITION' : 'CORE',
);

Map<String, List<DevelopmentIndicator>> _positionIndicators(
  PositionGroup? group,
) => switch (group) {
  PositionGroup.goalkeeper => {
    'technical': [
      _indicator(
        'handlingShotStopping',
        'Handling and shot-stopping',
        position: true,
      ),
      _indicator(
        'goalkeeperDistribution',
        'Goalkeeper distribution',
        position: true,
      ),
    ],
    'tactical': [
      _indicator(
        'anglesStartingPosition',
        'Angles and starting position',
        position: true,
      ),
      _indicator(
        'organisationSweeping',
        'Organisation and sweeping',
        position: true,
      ),
    ],
    'physical': [
      _indicator(
        'goalkeeperExplosiveness',
        'Goalkeeper explosive movement',
        position: true,
      ),
    ],
    'mental': [
      _indicator('goalkeeperComposure', 'Goalkeeper composure', position: true),
    ],
  },
  PositionGroup.defence => _lineAdditions(
    technical: const [
      ('defensiveTechnique', 'Defensive technique'),
      ('buildUpPassing', 'Build-up passing'),
    ],
    tactical: const [
      ('pressureCoverBalance', 'Pressure, cover, and balance'),
      ('defensiveLineDecisions', 'Line and build-up decisions'),
    ],
    physical: const ('defensiveDuelsMobility', 'Defensive duels and mobility'),
    mental: const ('defensiveDiscipline', 'Defensive discipline'),
  ),
  PositionGroup.midfield => _lineAdditions(
    technical: const [
      ('halfTurnReceiving', 'Receiving on the half-turn'),
      ('progressivePassing', 'Progressive passing'),
    ],
    tactical: const [
      ('supportTempo', 'Support and tempo'),
      ('midfieldTransitions', 'Midfield transitions'),
    ],
    physical: const ('midfieldRepeatMovement', 'Repeat midfield movement'),
    mental: const ('midfieldResponsibility', 'Responsibility under pressure'),
  ),
  PositionGroup.attack => _lineAdditions(
    technical: const [
      ('oneVOneDribbling', '1v1 and dribbling'),
      ('finishing', 'Finishing'),
    ],
    tactical: const [
      ('movementChanceCreation', 'Movement and chance creation'),
      ('attackingPressing', 'Attacking pressing'),
    ],
    physical: const (
      'attackingAcceleration',
      'Attacking acceleration and deceleration',
    ),
    mental: const ('attackingInitiative', 'Attacking initiative'),
  ),
  null => const {},
};

Map<String, List<DevelopmentIndicator>> _lineAdditions({
  required List<(String, String)> technical,
  required List<(String, String)> tactical,
  required (String, String) physical,
  required (String, String) mental,
}) => {
  'technical': [
    for (final item in technical) _indicator(item.$1, item.$2, position: true),
  ],
  'tactical': [
    for (final item in tactical) _indicator(item.$1, item.$2, position: true),
  ],
  'physical': [_indicator(physical.$1, physical.$2, position: true)],
  'mental': [_indicator(mental.$1, mental.$2, position: true)],
};
