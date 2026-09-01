from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('academy', '0027_tournament_tiers_and_training_conflicts')]

    operations = [
        migrations.CreateModel(
            name='PlayerStatsAssessment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('position', models.CharField(max_length=8)),
                ('role_group', models.CharField(max_length=20)),
                ('catalog_version', models.PositiveSmallIntegerField(default=1)),
                ('scores', models.JSONField()),
                ('overall', models.PositiveSmallIntegerField()),
                ('reason', models.CharField(max_length=100)),
                ('coach_notes', models.TextField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('assessed_by', models.ForeignKey(blank=True, limit_choices_to={'role': 'COACH'}, null=True, on_delete=models.SET_NULL, related_name='assessed_player_stats_assessments', to='accounts.user')),
                ('player', models.ForeignKey(limit_choices_to={'role': 'PLAYER'}, on_delete=models.CASCADE, related_name='player_stats_assessments', to='accounts.user')),
            ],
            options={'ordering': ['-created_at', '-id']},
        ),
        migrations.AddIndex(model_name='playerstatsassessment', index=models.Index(fields=['player', 'role_group', 'catalog_version', '-created_at'], name='academy_stats_compat_idx')),
        migrations.AddField(model_name='trainingsession', name='additional_focuses', field=models.JSONField(blank=True, default=list)),
        migrations.AddField(model_name='trainingsession', name='coach_instructions', field=models.TextField(blank=True, default='')),
        migrations.AddField(model_name='trainingsession', name='equipment_requirements', field=models.TextField(blank=True, default='')),
        migrations.AddField(model_name='trainingsession', name='session_objectives', field=models.TextField(blank=True, default='')),
    ]
