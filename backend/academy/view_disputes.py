"""Domain-focused API views extracted from the legacy view module."""

from ._view_support import *  # noqa: F401,F403
from .view_players import _require_unlock_when_pin_exists

def _dispute_in_user_scope(user, dispute):
    """True if `user` may act on `dispute` under club tenancy.

    Admin sees every club; coach/staff only disputes raised within their own
    club (a dispute's club is its raiser's club).
    """
    if user.role == Roles.ADMIN:
        return True
    return (
        user.club_id is not None
        and dispute.raised_by_id is not None
        and dispute.raised_by.club_id == user.club_id
    )


class DisputeListCreateView(APIView):
    """GET/POST /api/disputes/.

    GET: disputes visible to the caller (own club for coach/staff, all for
    Admin). POST: coach only — the coach flags, staff/admin respond via the
    thread endpoint.
    """

    def get(self, request):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not view disputes.')
        disputes = Dispute.objects.select_related(
            'raised_by', 'subject_player'
        ).prefetch_related('responses__author')
        # Tenancy: coach/staff see only their own club's disputes; Admin all.
        if request.user.role != Roles.ADMIN:
            if request.user.club_id is None:
                disputes = disputes.none()
            else:
                disputes = disputes.filter(
                    raised_by__club_id=request.user.club_id
                )
        return Response(DisputeSerializer(disputes, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can raise disputes.')
        if request.user.club_id is None:
            raise PermissionDenied('Coach account must belong to a club.')
        serializer = DisputeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        # Tenancy: the subject player, if any, must be in the coach's own club.
        subject_id = data.get('subjectPlayerId')
        if subject_id is not None and not User.objects.filter(
            pk=subject_id, club_id=request.user.club_id
        ).exists():
            raise PermissionDenied('That player is not in your club.')
        dispute = Dispute.objects.create(
            raised_by=request.user,
            subject_player_id=data.get('subjectPlayerId'),
            category=data['category'],
            summary=data['summary'],
            detail=data.get('detail') or '',
        )
        return Response(
            DisputeSerializer(dispute).data, status=status.HTTP_201_CREATED
        )


class DisputeDetailView(APIView):
    """GET /api/disputes/<pk>/ — one dispute with its full thread."""

    def get(self, request, pk):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not view disputes.')
        dispute = get_object_or_404(
            Dispute.objects.select_related('raised_by', 'subject_player')
            .prefetch_related('responses__author'),
            pk=pk,
        )
        if not _dispute_in_user_scope(request.user, dispute):
            raise PermissionDenied('You may not view this dispute.')
        return Response(DisputeSerializer(dispute).data)


class DisputeResponseCreateView(APIView):
    """POST /api/disputes/<pk>/responses/ — append to the thread.

    Append-only by design: no update/delete endpoints exist, so the thread is
    the dispute's audit trail. A response may carry a status change, applied
    to the parent atomically with the entry that documents it.
    """

    def post(self, request, pk):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not respond to disputes.')
        dispute = get_object_or_404(
            Dispute.objects.select_related('raised_by'), pk=pk
        )
        if not _dispute_in_user_scope(request.user, dispute):
            raise PermissionDenied('You may not respond to this dispute.')
        serializer = DisputeResponseCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        new_status = data.get('statusChangeTo')
        with transaction.atomic():
            DisputeResponse.objects.create(
                dispute=dispute,
                author=request.user,
                body=data['body'],
                status_change_to=new_status,
            )
            if new_status:
                dispute.status = new_status
            dispute.save()  # bumps updated_at even without a status change
        return Response(
            DisputeSerializer(dispute).data, status=status.HTTP_201_CREATED
        )


class EligibilityHistoryView(APIView):
    """GET /api/players/<id>/eligibility-history/ — a player's academic
    eligibility transitions, newest first.

    Object-scoped (audit finding F3): the player themselves, their linked
    guardian(s), School Staff, and Admin may read; nobody else — notably not
    the coach, since academic eligibility is not the coach's domain. The
    serializer hides the acting staff member's identity from families.
    """

    def get(self, request, player_id):
        if not _may_read_eligibility(request.user, player_id):
            # Authorized reviewers (Admin / School Staff) who named a player
            # that does not exist get a 404; a real player in another club still
            # falls through to the 403 below (multi-tenant scope). Families and
            # coaches get 403 without revealing whether the id exists.
            if request.user.role in (Roles.ADMIN, Roles.SCHOOL_STAFF):
                get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
            raise PermissionDenied(
                'You may not view this player\'s eligibility history.'
            )
        player = get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
        _require_unlock_when_pin_exists(request, player_id)
        if player.club_id is not None and not player.club.allows_academic_eligibility:
            return Response({'applicable': False, 'results': []})
        history = EligibilityHistory.objects.filter(
            player_id=player_id
        ).select_related('changed_by')
        return Response(
            EligibilityHistorySerializer(
                history, many=True, context={'request': request},
            ).data
        )
