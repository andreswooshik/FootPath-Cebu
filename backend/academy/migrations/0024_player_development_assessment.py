from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0023_player_growth'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='playerprofile',
            name='development_assessed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='playerprofile',
            name='development_framework_version',
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='playerprofile',
            name='development_scores',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='playerprofile',
            name='development_strengths',
            field=models.TextField(blank=True, default=''),
        ),
        migrations.AddField(
            model_name='playerprofile',
            name='development_targets',
            field=models.TextField(blank=True, default=''),
        ),
        migrations.CreateModel(
            name='PlayerDevelopmentAssessment',
            fields=[
                (
                    'id',
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name='ID',
                    ),
                ),
                ('position', models.CharField(blank=True, max_length=8)),
                (
                    'age_tier',
                    models.CharField(
                        choices=[
                            ('FOUNDATION', 'Foundation'),
                            ('DEVELOPMENT', 'Development'),
                            ('PATHWAY', 'Pathway'),
                        ],
                        max_length=20,
                    ),
                ),
                ('age_at_assessment', models.PositiveSmallIntegerField()),
                ('framework_version', models.PositiveSmallIntegerField()),
                ('scores', models.JSONField(default=dict)),
                ('strengths', models.TextField()),
                ('development_targets', models.TextField()),
                ('coach_notes', models.TextField(blank=True, default='')),
                (
                    'reason',
                    models.CharField(
                        choices=[
                            ('GENERAL_REVIEW', 'General review'),
                            ('MONTHLY_REVIEW', 'Monthly review'),
                            ('POST_TOURNAMENT', 'Post-tournament'),
                            ('RETURN_FROM_INJURY', 'Return from injury'),
                            ('BASELINE', 'Baseline'),
                            ('OTHER', 'Other'),
                        ],
                        default='GENERAL_REVIEW',
                        max_length=24,
                    ),
                ),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                (
                    'assessed_by',
                    models.ForeignKey(
                        blank=True,
                        limit_choices_to={'role': 'COACH'},
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name='player_development_assessments',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'player',
                    models.ForeignKey(
                        limit_choices_to={'role': 'PLAYER'},
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='development_assessments',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                'ordering': ['-created_at', '-id'],
                'indexes': [
                    models.Index(
                        fields=['player', '-created_at'],
                        name='academy_dev_player_date_idx',
                    ),
                ],
            },
        ),
    ]
