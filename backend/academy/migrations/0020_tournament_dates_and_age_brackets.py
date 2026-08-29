from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone
from django.core.validators import MaxValueValidator, MinValueValidator


def backfill_tournament_dates(apps, schema_editor):
    TournamentSchedule = apps.get_model('academy', 'TournamentSchedule')
    TournamentFixture = apps.get_model('academy', 'TournamentFixture')
    for schedule in TournamentSchedule.objects.all().iterator():
        first_fixture = (
            TournamentFixture.objects.filter(schedule_id=schedule.pk)
            .order_by('kickoff_at')
            .values_list('kickoff_at', flat=True)
            .first()
        )
        source = first_fixture or schedule.published_at or schedule.created_at
        schedule.starts_on = source.date()
        schedule.save(update_fields=['starts_on'])


class Migration(migrations.Migration):
    dependencies = [('academy', '0019_injury_confirmation_workflow')]

    operations = [
        migrations.AddField(
            model_name='tournamentschedule',
            name='starts_on',
            field=models.DateField(null=True),
        ),
        migrations.RunPython(backfill_tournament_dates, migrations.RunPython.noop),
        migrations.AlterField(
            model_name='tournamentschedule',
            name='starts_on',
            field=models.DateField(default=django.utils.timezone.localdate),
        ),
        migrations.AlterField(
            model_name='tournamentschedule',
            name='published_at',
            field=models.DateTimeField(
                blank=True, default=django.utils.timezone.now, null=True
            ),
        ),
        migrations.AlterModelOptions(
            name='tournamentschedule',
            options={'ordering': ['-starts_on', '-id']},
        ),
        migrations.CreateModel(
            name='TournamentAgeBracket',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('max_age', models.PositiveSmallIntegerField(validators=[MinValueValidator(3), MaxValueValidator(25)])),
                ('scheduled_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('schedule', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='age_brackets', to='academy.tournamentschedule')),
            ],
            options={
                'ordering': ['max_age', 'id'],
                'indexes': [models.Index(fields=['schedule', 'max_age'], name='academy_tourn_bracket_idx')],
                'constraints': [models.UniqueConstraint(fields=('schedule', 'max_age'), name='academy_unique_tournament_age_bracket')],
            },
        ),
    ]
