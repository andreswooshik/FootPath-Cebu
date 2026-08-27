from django.conf import settings
import django.core.validators
from django.db import migrations, models
import django.db.models.deletion


def backfill_rating_actors(apps, schema_editor):
    Performance = apps.get_model('academy', 'PlayerMatchPerformance')
    for row in Performance.objects.select_related('recorded_by').iterator():
        actor = row.recorded_by
        if row.coach_rating is not None and actor is not None and actor.role == 'COACH':
            row.rated_by_id = actor.id
            row.rated_at = row.updated_at
            row.save(update_fields=['rated_by', 'rated_at'])


class Migration(migrations.Migration):

    dependencies = [
        ('academy', '0017_tournament_schedule_and_fixture'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AlterField(
            model_name='playermatchperformance',
            name='coach_rating',
            field=models.DecimalField(blank=True, decimal_places=1, max_digits=3, null=True, validators=[django.core.validators.MinValueValidator(0), django.core.validators.MaxValueValidator(10)]),
        ),
        migrations.AddField(
            model_name='playermatchperformance',
            name='rated_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='playermatchperformance',
            name='rated_by',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='rated_match_performances', to=settings.AUTH_USER_MODEL),
        ),
        migrations.RunPython(backfill_rating_actors, migrations.RunPython.noop),
    ]
