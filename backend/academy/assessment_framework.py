"""Versioned FootPath grassroots development-assessment framework.

The framework is deliberately code-owned rather than editable in the database:
an immutable assessment must always be interpretable against the exact catalog
that validated it. A future catalog is introduced as a new version instead of
silently changing the meaning of historical scores.
"""
from decimal import Decimal, ROUND_HALF_UP


FRAMEWORK_VERSION = 1
FRAMEWORK_NAME = 'FootPath Development Framework'

SCALE = (
    {
        'value': 1,
        'label': 'Emerging',
        'description': 'Rarely demonstrated at the expected development level; frequent support is needed.',
    },
    {
        'value': 2,
        'label': 'Developing',
        'description': 'Sometimes demonstrated in simple situations or with support.',
    },
    {
        'value': 3,
        'label': 'Consistent',
        'description': 'Reliably demonstrated in typical age-appropriate training and match situations.',
    },
    {
        'value': 4,
        'label': 'Advanced',
        'description': 'Reliably demonstrated in pressured or complex situations.',
    },
    {
        'value': 5,
        'label': 'Leading',
        'description': 'Consistently excels under pressure and models the behaviour for others.',
    },
    {
        'value': None,
        'label': 'Not observed',
        'description': 'There was not enough recent evidence to rate this indicator.',
    },
)

DOMAIN_META = {
    'technical': {
        'label': 'Technical',
        'description': 'Quality and adaptability when executing football actions.',
    },
    'tactical': {
        'label': 'Tactical / Game Intelligence',
        'description': 'Reading the game, choosing actions, and using space.',
    },
    'physical': {
        'label': 'Physical / Coordinative',
        'description': 'Age-appropriate movement quality and football-specific capacity.',
    },
    'mental': {
        'label': 'Mental / Emotional',
        'description': 'Learning behaviour, confidence, composure, and response to challenge.',
    },
    'socialValues': {
        'label': 'Social / Values',
        'description': 'Humility, effort, ambition, respect, and teamwork in action.',
    },
}

CORE_INDICATORS = {
    'technical': (
        ('firstTouchBallControl', 'First touch and ball control', 'Prepares the next action with controlled, purposeful touches.'),
        ('passingReceiving', 'Passing and receiving', 'Connects accurately and receives with awareness of the next action.'),
        ('skillUnderPressure', 'Skill under pressure', 'Keeps useful technique when space or time is reduced.'),
    ),
    'tactical': (
        ('scanningAwareness', 'Scanning and awareness', 'Checks surroundings and recognizes teammates, opponents, and space.'),
        ('decisionMaking', 'Decision-making', 'Chooses an effective action for the game situation.'),
        ('positioningSpace', 'Positioning and use of space', 'Creates, protects, or closes useful space for the team.'),
    ),
    'physical': (
        ('coordinationBalance', 'Coordination and balance', 'Controls the body efficiently while changing football actions.'),
        ('agilityDirection', 'Agility and change of direction', 'Accelerates, brakes, and changes direction with control.'),
        ('repeatEffortEndurance', 'Repeat effort and endurance', 'Sustains useful football actions and recovers between efforts.'),
    ),
    'mental': (
        ('focusLearning', 'Focus and learning', 'Listens, applies feedback, and stays engaged with the task.'),
        ('confidenceCreativity', 'Confidence and creativity', 'Attempts solutions and expresses ideas without fear of mistakes.'),
        ('resilienceEmotionalControl', 'Resilience and emotional control', 'Responds constructively to errors, pressure, and setbacks.'),
    ),
    'socialValues': (
        ('humility', 'Humility', 'Accepts feedback, stays grounded, and values the contribution of others.'),
        ('effortCommitment', 'Effort and commitment', 'Shows dependable preparation and purposeful effort for the team.'),
        ('ambition', 'Ambition', 'Sets challenging goals and works deliberately to improve.'),
        ('respect', 'Respect', 'Treats teammates, opponents, officials, and staff appropriately.'),
        ('teamwork', 'Teamwork', 'Communicates, cooperates, and puts shared success into action.'),
    ),
}

POSITION_GROUPS = {
    'GK': 'GOALKEEPER',
    'CB': 'DEFENCE',
    'LB': 'DEFENCE',
    'RB': 'DEFENCE',
    'CDM': 'MIDFIELD',
    'CM': 'MIDFIELD',
    'CAM': 'MIDFIELD',
    'LW': 'ATTACK',
    'RW': 'ATTACK',
    'ST': 'ATTACK',
}

POSITION_INDICATORS = {
    'GOALKEEPER': {
        'technical': (
            ('handlingShotStopping', 'Handling and shot-stopping', 'Uses secure techniques to protect the goal and retain or divert the ball.'),
            ('goalkeeperDistribution', 'Goalkeeper distribution', 'Restarts accurately and with an appropriate technique.'),
        ),
        'tactical': (
            ('anglesStartingPosition', 'Angles and starting position', 'Adjusts position early to protect space and the goal.'),
            ('organisationSweeping', 'Organisation and sweeping', 'Communicates, supports the line, and manages space behind it.'),
        ),
        'physical': (
            ('goalkeeperExplosiveness', 'Goalkeeper explosive movement', 'Moves powerfully and safely in goalkeeper-specific actions.'),
        ),
        'mental': (
            ('goalkeeperComposure', 'Goalkeeper composure', 'Resets quickly and communicates calmly after high-pressure moments.'),
        ),
    },
    'DEFENCE': {
        'technical': (
            ('defensiveTechnique', 'Defensive technique', 'Uses appropriate body shape and technique in defensive actions.'),
            ('buildUpPassing', 'Build-up passing', 'Progresses or retains possession securely from the back line.'),
        ),
        'tactical': (
            ('pressureCoverBalance', 'Pressure, cover, and balance', 'Coordinates with teammates to protect dangerous space.'),
            ('defensiveLineDecisions', 'Line and build-up decisions', 'Recognizes when to step, drop, hold, or support possession.'),
        ),
        'physical': (
            ('defensiveDuelsMobility', 'Defensive duels and mobility', 'Moves and competes effectively while staying controlled.'),
        ),
        'mental': (
            ('defensiveDiscipline', 'Defensive discipline', 'Maintains concentration, patience, and responsibility when defending.'),
        ),
    },
    'MIDFIELD': {
        'technical': (
            ('halfTurnReceiving', 'Receiving on the half-turn', 'Receives in a shape that opens useful forward options.'),
            ('progressivePassing', 'Progressive passing', 'Breaks or shifts lines without forcing low-value actions.'),
        ),
        'tactical': (
            ('supportTempo', 'Support and tempo', 'Offers useful angles and helps control the speed of play.'),
            ('midfieldTransitions', 'Midfield transitions', 'Reacts early when possession changes.'),
        ),
        'physical': (
            ('midfieldRepeatMovement', 'Repeat midfield movement', 'Repeatedly supports play in and out of possession.'),
        ),
        'mental': (
            ('midfieldResponsibility', 'Responsibility under pressure', 'Continues requesting and using the ball in difficult moments.'),
        ),
    },
    'ATTACK': {
        'technical': (
            ('oneVOneDribbling', '1v1 and dribbling', 'Creates or protects an advantage when directly opposed.'),
            ('finishing', 'Finishing', 'Selects and executes an appropriate final action near goal.'),
        ),
        'tactical': (
            ('movementChanceCreation', 'Movement and chance creation', 'Times movement to receive, combine, or open space for others.'),
            ('attackingPressing', 'Attacking pressing', 'Recognizes cues and works with teammates to regain or delay possession.'),
        ),
        'physical': (
            ('attackingAcceleration', 'Attacking acceleration and deceleration', 'Changes speed sharply and under control to create separation.'),
        ),
        'mental': (
            ('attackingInitiative', 'Attacking initiative', 'Persists and takes responsible initiative after unsuccessful actions.'),
        ),
    },
}

AGE_GUIDANCE = {
    'FOUNDATION': {
        'technical': 'Prioritize enjoyment, repetition, both feet, and control in simple game situations.',
        'tactical': 'Judge recognition of simple space, teammates, opponents, and basic choices.',
        'physical': 'Judge movement quality and coordination; do not reward early size or strength advantages.',
        'mental': 'Look for curiosity, confidence to try, attention, and a healthy response to mistakes.',
        'socialValues': 'Use observable habits in training and games, explained in age-appropriate language.',
    },
    'DEVELOPMENT': {
        'technical': 'Judge reliable execution as pressure, speed, and tactical purpose increase.',
        'tactical': 'Judge scanning, combinations, transitions, and growing positional responsibility.',
        'physical': 'Judge controlled speed, repeat movement, and safe development rather than physique alone.',
        'mental': 'Look for ownership of learning, composure, creativity, and persistence under pressure.',
        'socialValues': 'Judge repeatable behaviours that support teammates and the learning environment.',
    },
    'PATHWAY': {
        'technical': 'Judge match-specific consistency, adaptability, and execution under realistic pressure.',
        'tactical': 'Judge independent reading of the game, role discipline, and influence on team solutions.',
        'physical': 'Judge football-specific readiness and repeatability while respecting safe load management.',
        'mental': 'Look for self-regulation, accountability, leadership, and response to performance demands.',
        'socialValues': 'Judge consistent standards and positive influence within the team environment.',
    },
}


class AssessmentFrameworkError(ValueError):
    def __init__(self, errors):
        super().__init__('Invalid development assessment scores.')
        self.errors = errors


def position_group(position):
    return POSITION_GROUPS.get((position or '').upper())


def framework_for(age_tier, position):
    tier = age_tier if age_tier in AGE_GUIDANCE else 'DEVELOPMENT'
    group = position_group(position)
    additions = POSITION_INDICATORS.get(group, {})
    domains = []
    for key, meta in DOMAIN_META.items():
        indicators = [
            {
                'key': indicator_key,
                'label': label,
                'description': description,
                'scope': 'CORE',
            }
            for indicator_key, label, description in CORE_INDICATORS[key]
        ]
        indicators.extend(
            {
                'key': indicator_key,
                'label': label,
                'description': description,
                'scope': 'POSITION',
            }
            for indicator_key, label, description in additions.get(key, ())
        )
        domains.append({
            'key': key,
            **meta,
            'guidance': AGE_GUIDANCE[tier][key],
            'minimumObserved': (len(indicators) + 1) // 2,
            'indicators': indicators,
        })
    return {
        'version': FRAMEWORK_VERSION,
        'name': FRAMEWORK_NAME,
        'methodology': 'FIFA-aligned, Barça-inspired holistic player development.',
        'disclaimer': 'A FootPath framework; not an official FIFA or FC Barcelona assessment tool.',
        'ageTier': tier,
        'position': position or '',
        'positionGroup': group,
        'scale': list(SCALE),
        'domains': domains,
    }


def validate_scores(raw_scores, *, age_tier, position, version):
    if version != FRAMEWORK_VERSION:
        raise AssessmentFrameworkError({
            'frameworkVersion': f'Only framework version {FRAMEWORK_VERSION} is supported.',
        })
    if not isinstance(raw_scores, dict):
        raise AssessmentFrameworkError({
            'developmentRatings': 'Use an object grouped by assessment domain.',
        })

    framework = framework_for(age_tier, position)
    expected_domains = {domain['key']: domain for domain in framework['domains']}
    errors = {}
    missing_domains = sorted(set(expected_domains) - set(raw_scores))
    unknown_domains = sorted(set(raw_scores) - set(expected_domains))
    if missing_domains:
        errors['missingDomains'] = missing_domains
    if unknown_domains:
        errors['unknownDomains'] = unknown_domains

    cleaned = {}
    for domain_key, domain in expected_domains.items():
        raw_domain = raw_scores.get(domain_key)
        if not isinstance(raw_domain, dict):
            errors[domain_key] = 'Use an object containing every applicable indicator.'
            continue
        expected_keys = {
            indicator['key'] for indicator in domain['indicators']
        }
        missing = sorted(expected_keys - set(raw_domain))
        unknown = sorted(set(raw_domain) - expected_keys)
        domain_errors = {}
        if missing:
            domain_errors['missingIndicators'] = missing
        if unknown:
            domain_errors['unknownIndicators'] = unknown

        normalized = {}
        observed = 0
        for indicator in domain['indicators']:
            key = indicator['key']
            if key not in raw_domain:
                continue
            value = raw_domain[key]
            if value is not None and (
                type(value) is not int or value < 1 or value > 5
            ):
                domain_errors[key] = 'Use an integer from 1 to 5 or null for Not observed.'
                continue
            normalized[key] = value
            if value is not None:
                observed += 1
        if observed < domain['minimumObserved']:
            domain_errors['minimumObserved'] = (
                f'Rate at least {domain["minimumObserved"]} indicators in this domain.'
            )
        if domain_errors:
            errors[domain_key] = domain_errors
        cleaned[domain_key] = normalized

    if errors:
        raise AssessmentFrameworkError({'developmentRatings': errors})
    return cleaned


def rounded_mean(values, digits=1):
    clean = [Decimal(str(value)) for value in values if value is not None]
    if not clean:
        return None
    quantum = Decimal('1').scaleb(-digits)
    return float(
        (sum(clean, Decimal('0')) / len(clean)).quantize(
            quantum,
            rounding=ROUND_HALF_UP,
        )
    )


def domain_scores(scores):
    scores = scores if isinstance(scores, dict) else {}
    return {
        key: rounded_mean(
            list(domain.values()) if isinstance(domain, dict) else []
        )
        for key in DOMAIN_META
        for domain in [scores.get(key, {})]
    }
