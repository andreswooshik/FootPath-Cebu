from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0012_playerprivacypin'),
    ]

    operations = [
        migrations.AddIndex(
            model_name='attendance',
            index=models.Index(
                fields=['session', 'status'],
                name='academy_att_session_status_idx',
            ),
        ),
        migrations.AddIndex(
            model_name='injuryrecord',
            index=models.Index(
                fields=['player', '-occurred_on'],
                name='academy_injury_player_date_idx',
            ),
        ),
    ]
