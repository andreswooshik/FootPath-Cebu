"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Avg, Count, Prefetch, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import GuardianLink, Roles, User
from accounts.guardian_access import guardian_can_access_player, valid_guardian_links
from accounts.permissions import IsAdmin
from accounts.serializers import UserSerializer
from accounts.services import (
    ProvisioningError,
    provision_player,
)

from .assessment_framework import framework_for
from .models import (
    AgeTierSetting,
    AssessmentReason,
    Attendance,
    AttendanceStatus,
    AuditLog,
    ConfirmationStatus,
    DeviceToken,
    Dispute,
    DisputeResponse,
    EligibilityHistory,
    FixtureStatus,
    FootballMatch,
    MatchCategory,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    NotificationRecord,
    PlayerMatchPerformance,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerStatsAssessment,
    PlayerProfile,
    PlayerPrivacyPin,
    SessionConfirmation,
    TrainingSession,
    TrainingSessionStatus,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from .notifications import (
    _recipients_for_session,
    notify_assessment_saved,
    notify_session_cancelled,
    notify_session_scheduled,
    notify_session_updated,
    notify_tournament_roster_published,
)
from .pin_service import (
    InvalidCurrentPin,
    InvalidPin,
    PinLocked,
    PinNotSet,
    reset_pin,
    set_pin,
    verify_pin,
    pin_status,
    has_pin,
)
from .serializers import (
    AdminCreatePlayerSerializer,
    AgeTierSettingSerializer,
    AssessmentSerializer,
    DevelopmentAssessmentWriteSerializer,
    AttendanceSerializer,
    DisputeCreateSerializer,
    DisputeResponseCreateSerializer,
    DisputeSerializer,
    EligibilityHistorySerializer,
    CoachMatchRatingSerializer,
    FootballMatchSerializer,
    InjuryRecordSerializer,
    InjuryStatusUpdateRequestSerializer,
    NotificationRecordSerializer,
    PlayerMatchPerformanceSerializer,
    PlayerAssessmentSnapshotSerializer,
    PlayerDevelopmentAssessmentSerializer,
    PlayerStatsAssessmentSerializer,
    PlayerStatsAssessmentWriteSerializer,
    PlayerMatchStatisticsWriteSerializer,
    PlayerPositionSerializer,
    PlayerSerializer,
    PlayerSelectorSerializer,
    SessionAttendanceRecordSerializer,
    SessionConfirmationSerializer,
    TrainingSessionSerializer,
    TournamentAgeBracketWriteSerializer,
    TournamentFixtureResultWriteSerializer,
    TournamentFixtureWriteSerializer,
    TournamentScheduleSerializer,
    TournamentScheduleWriteSerializer,
    TournamentSquadSerializer,
    TournamentSquadWriteSerializer,
)
from .match_statistics import build_performance_summary
from .growth import (
    build_assessment_growth,
    build_development_assessment_growth,
    build_match_growth,
    build_tournament_groups,
    build_training_groups,
    limited,
    resolve_growth_filter,
)
from .player_unlock import issue_player_unlock, require_player_unlock
from .storage import (
    delete_photo,
    delete_tournament_document,
    invalidate_signed_photo_url,
    invalidate_signed_tournament_document_url,
    sanitized_photo_bytes,
    sanitized_tournament_document_bytes,
    upload_photo,
    upload_tournament_document,
    validate_photo_upload,
    validate_tournament_document,
)
from .tournament_results import complete_tournament_fixture
from .tournament_rosters import invalid_squad_entries, roster_eligibility
from .schedule_conflicts import (
    cancel_conflicting_training,
    conflicting_fixture_for_training,
    conflicting_training_for_fixtures,
    fixture_conflict_payload,
    training_conflicts_for_training,
)
from .player_stats import catalog_for, overall, role_group_for

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)


class WorkflowConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_code = 'conflict'

    def __init__(self, code, message, **details):
        super().__init__({'code': code, 'message': message, **details})


def _confirmed(request, field='confirmTrainingCancellations'):
    return str(request.data.get(field, '')).lower() in ('true', '1', 'yes', 'on')


def _training_cancellation_details(conflicts):
    return {
        'count': len(conflicts),
        'sessions': [
            {
                'id': str(session.id),
                'title': session.title,
                'date': session.date.isoformat(),
                'startTime': session.start_time,
                'endTime': session.end_time,
                'ageTiers': session.age_tiers,
                'fixture': fixture_conflict_payload(fixture),
            }
            for session, fixture in conflicts
        ],
    }


def _in_same_club(user, player_id):
    """True if `player_id` names a user in `user`'s club (multi-tenant scope).

    A missing requester club always fails closed: legacy club-less accounts are
    not a shared tenant. ADMIN is club-less by design and is handled by an
    explicit cross-club branch before this helper is called.
    """
    if user.club_id is None:
        return False
    row = User.objects.filter(pk=player_id).values('club_id').first()
    return row is not None and row['club_id'] == user.club_id


def _guardian_may_read(user, player_id):
    """True if `user` is allowed to read the given player's data."""
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.COACH:
        # Coaches are club-scoped: only players in their own club (tenancy).
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return guardian_can_access_player(user, player_id)
    return False


def _may_read_match_statistics(user, player_id):
    """Authorize the player and the adults responsible for their development."""
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.COACH:
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return guardian_can_access_player(user, player_id)
    return False


def _may_read_eligibility(user, player_id):
    """True if `user` may read a player's eligibility history.

    Deliberately narrower than [_guardian_may_read]: the coach is excluded —
    academic eligibility is the School Staff's domain, not the coach's. Allowed:
    the player themselves, their linked guardian(s), any School Staff (in the
    same club), Admin.
    """
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.SCHOOL_STAFF:
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return guardian_can_access_player(user, player_id)
    return False


def _sessions_for(user):
    """The TrainingSession queryset visible to `user`: their own club's
    sessions, or every club's for Admin."""
    qs = TrainingSession.objects.annotate(
        present_attendee_count=Count(
            'attendance_records',
            filter=Q(attendance_records__status=AttendanceStatus.PRESENT),
        )
    )
    if user.role == Roles.ADMIN:
        return qs
    if user.club_id is None:
        return qs.none()
    return qs.filter(club_id=user.club_id)


def _session_in_user_scope(user, session):
    """True if `user` may see/act on `session` under club tenancy (Admin: any
    club; everyone else: only their own club's sessions)."""
    if user.role == Roles.ADMIN:
        return True
    return user.club_id is not None and session.club_id == user.club_id


def _matches_for(user):
    """Club-scoped match queryset; Admin can inspect every club."""
    qs = FootballMatch.objects.select_related(
        'club', 'created_by', 'source_fixture__age_bracket',
    )
    if user.role == Roles.ADMIN:
        return qs
    if user.club_id is None:
        return qs.none()
    return qs.filter(club_id=user.club_id)


def _role_match(request, match_id, role):
    """Return a same-club match for one explicit role."""
    if request.user.role != role:
        raise PermissionDenied(f'Only {role.lower()} accounts can perform this action.')
    if request.user.club_id is None:
        raise PermissionDenied('Your account must belong to a club.')
    return get_object_or_404(
        FootballMatch.objects.select_related(
            'club', 'source_fixture__age_bracket__schedule',
        ),
        pk=match_id,
        club_id=request.user.club_id,
    )


def _match_age_bracket(match):
    """Return a linked age bracket without breaking legacy/ad-hoc matches."""
    try:
        return match.source_fixture.age_bracket
    except TournamentFixture.DoesNotExist:
        return None



__all__ = [name for name in globals() if not name.startswith('__')]
