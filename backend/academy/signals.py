"""Model signals — history + pushes that must fire regardless of the write path.

Eligibility is edited from the Django admin, the console, and (in future) an
API endpoint. A view-level hook would cover exactly one of those, so the
change detection lives on the model's save cycle instead: pre_save stashes the
stored value, post_save compares, then records an append-only history row and
fires the push.
"""
from django.db import transaction
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from .models import AuditLog, EligibilityHistory, PlayerProfile
from .notifications import notify_eligibility_changed


@receiver(pre_save, sender=PlayerProfile)
def stash_previous_eligibility(sender, instance, **kwargs):
    if instance.pk:
        instance._previous_eligibility = (
            sender.objects.filter(pk=instance.pk)
            .values_list('eligibility', flat=True)
            .first()
        )
    else:
        instance._previous_eligibility = None


@receiver(post_save, sender=PlayerProfile)
def fire_eligibility_changed(sender, instance, created, **kwargs):
    previous = getattr(instance, '_previous_eligibility', None)
    # A new profile or an unchanged value is not a transition — nothing to
    # record or announce.
    if created or previous is None or previous == instance.eligibility:
        return
    if (
        instance.user.club_id is not None
        and not instance.user.club.allows_academic_eligibility
    ):
        # The stored default is kept for schema compatibility, but Independent
        # clubs have no academic feature, history, or notifications.
        return
    # Append-only history row, written in the same transaction as the change so
    # a rolled-back edit leaves no trail. changed_by is stashed on the instance
    # by the write path (admin save_model / a view); null when unknown.
    EligibilityHistory.objects.create(
        player_id=instance.user_id,
        changed_by=getattr(instance, '_changed_by', None),
        old_status=previous or '',
        new_status=instance.eligibility,
    )
    # Mirrored into the general audit log so one place holds every sensitive
    # change; EligibilityHistory stays the family-facing, object-scoped trail.
    AuditLog.record(
        getattr(instance, '_changed_by', None),
        'eligibility.changed',
        target=instance.user.email,
        detail=f'{previous} → {instance.eligibility}',
    )
    # Push only after the row is durably committed; a rolled-back change must
    # not notify anyone.
    transaction.on_commit(
        lambda: notify_eligibility_changed(instance, previous)
    )
