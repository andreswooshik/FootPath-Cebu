from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0024_player_development_assessment'),
    ]

    operations = [
        migrations.AddField(
            model_name='tournamentschedule',
            name='venue',
            field=models.CharField(blank=True, max_length=160),
        ),
        migrations.AlterField(
            model_name='tournamentagebracket',
            name='max_age',
            field=models.PositiveSmallIntegerField(
                validators=[MinValueValidator(3), MaxValueValidator(21)],
            ),
        ),
    ]
