from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ('academy', '0016_footballmatch_playermatchperformance_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='TournamentSchedule',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=120)),
                ('document_path', models.CharField(blank=True, max_length=500)),
                ('is_published', models.BooleanField(default=True)),
                ('published_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('club', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='tournament_schedules', to='accounts.club')),
                ('uploaded_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='uploaded_tournament_schedules', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-published_at', '-id'],
            },
        ),
        migrations.CreateModel(
            name='TournamentFixture',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('stage', models.CharField(blank=True, max_length=80)),
                ('opponent', models.CharField(default='TBD', max_length=120)),
                ('kickoff_at', models.DateTimeField()),
                ('venue', models.CharField(choices=[('HOME', 'Home'), ('AWAY', 'Away'), ('NEUTRAL', 'Neutral')], default='NEUTRAL', max_length=10)),
                ('location', models.CharField(blank=True, max_length=160)),
                ('status', models.CharField(choices=[('SCHEDULED', 'Scheduled'), ('POSTPONED', 'Postponed'), ('CANCELLED', 'Cancelled'), ('COMPLETED', 'Completed')], default='SCHEDULED', max_length=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('completed_match', models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='source_fixture', to='academy.footballmatch')),
                ('schedule', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='fixtures', to='academy.tournamentschedule')),
            ],
            options={
                'ordering': ['kickoff_at', 'id'],
            },
        ),
        migrations.AddIndex(
            model_name='tournamentschedule',
            index=models.Index(fields=['club', '-published_at'], name='academy_tourn_club_pub_idx'),
        ),
        migrations.AddIndex(
            model_name='tournamentfixture',
            index=models.Index(fields=['schedule', 'kickoff_at'], name='academy_fixture_sched_idx'),
        ),
    ]
