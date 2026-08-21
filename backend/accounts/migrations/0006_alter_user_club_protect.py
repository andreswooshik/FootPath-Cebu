import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0005_user_one_coordinator_per_club_and_role_label'),
    ]

    operations = [
        migrations.AlterField(
            model_name='user',
            name='club',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='members',
                to='accounts.club',
            ),
        ),
    ]
