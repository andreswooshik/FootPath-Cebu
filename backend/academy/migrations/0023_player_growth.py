from django.conf import settings
from django.db import migrations, models
import django.core.validators
import django.db.models.deletion


def seed_growth_baselines(apps, schema_editor):
    PlayerProfile = apps.get_model('academy', 'PlayerProfile')
    Snapshot = apps.get_model('academy', 'PlayerAssessmentSnapshot')
    Attendance = apps.get_model('academy', 'Attendance')
    FootballMatch = apps.get_model('academy', 'FootballMatch')

    snapshots = []
    for profile in PlayerProfile.objects.all().iterator():
        snapshots.append(
            Snapshot(
                player_id=profile.user_id,
                assessed_by_id=None,
                position=profile.position,
                pace=profile.pace,
                shooting=profile.shooting,
                passing=profile.passing,
                dribbling=profile.dribbling,
                defending=profile.defending,
                physical=profile.physical,
                diving=profile.diving,
                handling=profile.handling,
                kicking=profile.kicking,
                reflexes=profile.reflexes,
                speed=profile.speed,
                positioning=profile.positioning,
                coach_notes=profile.coach_notes,
                reason='BASELINE',
            )
        )
    Snapshot.objects.bulk_create(snapshots, batch_size=500)

    # A non-present result cannot truthfully retain participation measures.
    Attendance.objects.exclude(status='PRESENT').update(
        effort=None,
        performance_score=None,
    )
    FootballMatch.objects.filter(source_fixture__isnull=False).update(
        category='TOURNAMENT'
    )


def noop_reverse(apps, schema_editor):
    # Baselines are real migration evidence and must not be guessed again.
    pass


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0022_tournament_match_roster_enforcement'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='PlayerAssessmentSnapshot',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('position', models.CharField(blank=True, max_length=8)),
                ('pace', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('shooting', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('passing', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('dribbling', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('defending', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('physical', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('diving', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('handling', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('kicking', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('reflexes', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('speed', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('positioning', models.PositiveSmallIntegerField(validators=[django.core.validators.MaxValueValidator(99)])),
                ('coach_notes', models.TextField(blank=True, default='')),
                ('reason', models.CharField(choices=[('GENERAL_REVIEW', 'General review'), ('MONTHLY_REVIEW', 'Monthly review'), ('POST_TOURNAMENT', 'Post-tournament'), ('RETURN_FROM_INJURY', 'Return from injury'), ('BASELINE', 'Baseline'), ('OTHER', 'Other')], default='GENERAL_REVIEW', max_length=24)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('assessed_by', models.ForeignKey(blank=True, limit_choices_to={'role': 'COACH'}, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='player_assessment_snapshots', to=settings.AUTH_USER_MODEL)),
                ('player', models.ForeignKey(limit_choices_to={'role': 'PLAYER'}, on_delete=django.db.models.deletion.CASCADE, related_name='assessment_snapshots', to=settings.AUTH_USER_MODEL)),
            ],
            options={'ordering': ['-created_at', '-id']},
        ),
        migrations.AddField(
            model_name='attendance',
            name='performance_score',
            field=models.DecimalField(blank=True, decimal_places=1, max_digits=3, null=True, validators=[django.core.validators.MinValueValidator(0), django.core.validators.MaxValueValidator(10)]),
        ),
        migrations.AddField(
            model_name='footballmatch',
            name='category',
            field=models.CharField(choices=[('FRIENDLY', 'Friendly'), ('LEAGUE', 'League'), ('TOURNAMENT', 'Tournament'), ('OTHER', 'Other')], default='OTHER', max_length=20),
        ),
        migrations.AddIndex(
            model_name='playerassessmentsnapshot',
            index=models.Index(fields=['player', '-created_at'], name='academy_assess_player_date_idx'),
        ),
        migrations.AddIndex(
            model_name='attendance',
            index=models.Index(fields=['player', '-updated_at'], name='academy_att_player_date_idx'),
        ),
        migrations.AddIndex(
            model_name='footballmatch',
            index=models.Index(fields=['club', 'category', '-played_on'], name='academy_match_category_idx'),
        ),
        migrations.RunPython(seed_growth_baselines, noop_reverse),
        migrations.AddConstraint(
            model_name='attendance',
            constraint=models.CheckConstraint(condition=models.Q(('status', 'PRESENT'), models.Q(('effort__isnull', True), ('performance_score__isnull', True)), _connector='OR'), name='attendance_scores_require_present'),
        ),
        migrations.AddConstraint(
            model_name='attendance',
            constraint=models.CheckConstraint(condition=models.Q(('effort__isnull', True), models.Q(('effort__gte', 0), ('effort__lte', 100)), _connector='OR'), name='attendance_effort_0_100'),
        ),
        migrations.AddConstraint(
            model_name='attendance',
            constraint=models.CheckConstraint(condition=models.Q(('performance_score__isnull', True), models.Q(('performance_score__gte', 0), ('performance_score__lte', 10)), _connector='OR'), name='attendance_performance_0_10'),
        ),
    ]
