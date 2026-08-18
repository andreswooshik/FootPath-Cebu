from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0004_club_coach_license_club_cvfa_membership_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='user',
            name='role',
            field=models.CharField(
                choices=[
                    ('ADMIN', 'Super Admin'),
                    ('COORDINATOR', 'Club Coordinator'),
                    ('COACH', 'Coach'),
                    ('PLAYER', 'Player'),
                    ('SCHOOL_STAFF', 'School Staff'),
                    ('GUARDIAN', 'Guardian'),
                ],
                default='PLAYER',
                max_length=20,
            ),
        ),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(
                condition=models.Q(('role', 'COORDINATOR')),
                fields=('club',),
                name='one_coordinator_per_club',
            ),
        ),
    ]
