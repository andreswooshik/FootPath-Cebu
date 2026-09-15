from django.db import migrations


def purge_coordinator_deleted_players(apps, schema_editor):
    """Finish player deletions made before they became hard deletes."""
    AuditLog = apps.get_model('academy', 'AuditLog')
    TournamentSquadEntry = apps.get_model('academy', 'TournamentSquadEntry')
    PlayerRegistration = apps.get_model('accounts', 'PlayerRegistration')
    User = apps.get_model('accounts', 'User')

    deleted_ids = []
    for target in AuditLog.objects.filter(action='player.deleted').values_list(
        'target', flat=True
    ):
        try:
            deleted_ids.append(int(target))
        except (TypeError, ValueError):
            continue

    player_ids = list(
        User.objects.filter(
            pk__in=deleted_ids,
            role='PLAYER',
            is_active=False,
        ).values_list('pk', flat=True)
    )
    if not player_ids:
        return

    PlayerRegistration.objects.filter(player_id__in=player_ids).delete()
    TournamentSquadEntry.objects.filter(player_id__in=player_ids).delete()
    User.objects.filter(pk__in=player_ids).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0012_alter_user_role'),
        ('academy', '0034_alter_trainingsession_date'),
    ]

    operations = [
        migrations.RunPython(
            purge_coordinator_deleted_players,
            migrations.RunPython.noop,
        ),
    ]
