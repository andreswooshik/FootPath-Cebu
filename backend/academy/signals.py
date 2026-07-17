"""Model signals — pushes that must fire regardless of the write path.

Eligibility is edited from the Django admin, the console, and (in future) an
API endpoint. A view-level hook would cover exactly one of those, so the
change detection lives on the model's save cycle instead: pre_save stashes the
stored value, post_save compares and fires after commit.
"""
from django.db import transaction
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from .models import PlayerProfile
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
    # A new profile or an unchanged value is not a transition — no push.
    if created or previous is None or previous == instance.eligibility:
        return
    # Only after the row is durably committed; a rolled-back change must not
    # notify anyone.
    transaction.on_commit(
        lambda: notify_eligibility_changed(instance, previous)
    )
