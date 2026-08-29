from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0021_tournament_squads'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='tournamentfixture',
            name='age_bracket',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='fixtures',
                to='academy.tournamentagebracket',
            ),
        ),
        migrations.AddField(
            model_name='playermatchperformance',
            name='squad_override_reason',
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name='playermatchperformance',
            name='squad_override_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='playermatchperformance',
            name='squad_override_by',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='approved_match_squad_overrides',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddConstraint(
            model_name='playermatchperformance',
            constraint=models.CheckConstraint(
                condition=(
                    models.Q(
                        squad_override_reason='',
                        squad_override_at__isnull=True,
                    )
                    | (
                        ~models.Q(squad_override_reason='')
                        & models.Q(squad_override_at__isnull=False)
                    )
                ),
                name='squad_override_reason_requires_timestamp',
            ),
        ),
    ]
