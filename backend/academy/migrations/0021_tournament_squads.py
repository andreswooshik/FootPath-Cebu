from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0020_tournament_dates_and_age_brackets'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='TournamentSquad',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('status', models.CharField(choices=[('DRAFT', 'Draft'), ('PUBLISHED', 'Published')], default='DRAFT', max_length=20)),
                ('published_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('bracket', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='squad', to='academy.tournamentagebracket')),
                ('updated_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='updated_tournament_squads', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='TournamentSquadEntry',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('position', models.CharField(blank=True, max_length=8)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('added_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='added_tournament_squad_entries', to=settings.AUTH_USER_MODEL)),
                ('player', models.ForeignKey(limit_choices_to={'role': 'PLAYER'}, on_delete=django.db.models.deletion.PROTECT, related_name='tournament_squad_entries', to=settings.AUTH_USER_MODEL)),
                ('squad', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='entries', to='academy.tournamentsquad')),
            ],
            options={
                'ordering': ['player__last_name', 'player__first_name', 'player_id'],
                'indexes': [models.Index(fields=['squad', 'player'], name='academy_tourn_squad_player_idx')],
                'constraints': [models.UniqueConstraint(fields=('squad', 'player'), name='academy_unique_tournament_squad_player')],
            },
        ),
    ]
