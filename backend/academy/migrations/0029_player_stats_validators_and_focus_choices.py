from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('academy', '0028_player_stats_and_training_details')]

    operations = [
        migrations.AlterField(
            model_name='playerstatsassessment',
            name='overall',
            field=models.PositiveSmallIntegerField(
                validators=[MinValueValidator(0), MaxValueValidator(99)]
            ),
        ),
        migrations.AlterField(
            model_name='trainingsession',
            name='focus',
            field=models.CharField(
                choices=[
                    ('TECHNICAL', 'Technical'),
                    ('PHYSICAL', 'Physical'),
                    ('MENTAL', 'Mental'),
                    ('TACTICAL', 'Tactical'),
                    ('RECOVERY', 'Recovery'),
                    ('MATCH_PREPARATION', 'Match Preparation'),
                ],
                default='TECHNICAL',
                max_length=20,
            ),
        ),
    ]
