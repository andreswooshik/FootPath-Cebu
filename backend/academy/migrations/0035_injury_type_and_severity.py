from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('academy', '0034_alter_trainingsession_date'),
    ]

    operations = [
        migrations.AddField(
            model_name='injuryrecord',
            name='injury_type',
            field=models.CharField(
                choices=[
                    ('MUSCLE', 'Muscle'),
                    ('JOINT_LIGAMENT', 'Joint / ligament'),
                    ('BONE', 'Bone'),
                    ('HEAD_FACE', 'Head / face'),
                    ('OTHER', 'Other'),
                ],
                default='OTHER',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='injuryrecord',
            name='severity',
            field=models.CharField(
                choices=[
                    ('MINOR', 'Minor'),
                    ('MODERATE', 'Moderate'),
                    ('SEVERE', 'Severe'),
                ],
                default='MODERATE',
                max_length=20,
            ),
        ),
    ]
