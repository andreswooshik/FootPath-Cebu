from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academy', '0025_tournament_venue_and_u21_limit'),
    ]

    operations = [
        migrations.AlterField(
            model_name='tournamentschedule',
            name='is_published',
            field=models.BooleanField(default=False),
        ),
        migrations.AlterField(
            model_name='tournamentschedule',
            name='published_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
