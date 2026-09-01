from datetime import timedelta

from django.db import migrations, models


def backfill_intervals_and_tiers(apps, schema_editor):
    TournamentAgeBracket = apps.get_model('academy', 'TournamentAgeBracket')
    TournamentFixture = apps.get_model('academy', 'TournamentFixture')
    for bracket in TournamentAgeBracket.objects.filter(academy_tiers=[]):
        if bracket.max_age <= 12:
            tiers = ['FOUNDATION']
        elif bracket.max_age <= 15:
            tiers = ['DEVELOPMENT']
        else:
            tiers = ['PATHWAY']
        bracket.academy_tiers = tiers
        bracket.save(update_fields=['academy_tiers'])
    for fixture in TournamentFixture.objects.filter(ends_at__isnull=True):
        fixture.ends_at = fixture.kickoff_at + timedelta(hours=2)
        fixture.save(update_fields=['ends_at'])


class Migration(migrations.Migration):
    dependencies = [('academy', '0026_tournament_draft_default')]

    operations = [
        migrations.AddField(
            model_name='tournamentagebracket',
            name='academy_tiers',
            field=models.JSONField(default=list),
        ),
        migrations.AddField(
            model_name='tournamentfixture',
            name='ends_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='status',
            field=models.CharField(
                choices=[
                    ('SCHEDULED', 'Scheduled'),
                    ('COMPLETED', 'Completed'),
                    ('CANCELLED', 'Cancelled'),
                ],
                default='SCHEDULED',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='cancellation_reason',
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='conflicting_tournament_id',
            field=models.PositiveBigIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='conflicting_fixture_id',
            field=models.PositiveBigIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='cancelled_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trainingsession',
            name='cancelled_by_action',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.RunPython(backfill_intervals_and_tiers, migrations.RunPython.noop),
    ]
