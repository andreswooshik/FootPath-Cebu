"""Transaction boundaries for competing club scheduling writes."""

from functools import wraps

from django.db import transaction

from accounts.models import Club


def club_write_transaction(view):
    """Lock the tenant before reading or changing its schedule.

    Works with APIView methods and Django function views. All scheduling
    writers acquire this stable row before child rows, including when a
    club has no existing bookings. Safe HTTP methods remain read-only.
    """

    @wraps(view)
    def wrapped(*args, **kwargs):
        request = args[0] if hasattr(args[0], 'method') else args[1]
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return view(*args, **kwargs)
        with transaction.atomic():
            club_id = getattr(request.user, 'club_id', None)
            if club_id is not None:
                Club.objects.select_for_update().get(pk=club_id)
            return view(*args, **kwargs)

    return wrapped
