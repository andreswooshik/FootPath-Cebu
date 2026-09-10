"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""

from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import PermissionDenied

from accounts.guardian_access import guardian_can_access_player
from accounts.models import Roles, User

from .models import (
    AttendanceStatus,
    FootballMatch,
    TournamentFixture,
    TrainingSession,
)
from .schedule_conflicts import fixture_conflict_payload

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)


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
        'club',
        'created_by',
        'source_fixture__age_bracket',
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
            'club',
            'source_fixture__age_bracket__schedule',
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
