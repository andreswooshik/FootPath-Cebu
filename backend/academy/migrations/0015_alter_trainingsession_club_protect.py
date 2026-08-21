import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academy', '0014_notificationrecord'),
        ('accounts', '0006_alter_user_club_protect'),
    ]

    operations = [
        migrations.AlterField(
            model_name='trainingsession',
            name='club',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='training_sessions',
                to='accounts.club',
            ),
        ),
    ]
