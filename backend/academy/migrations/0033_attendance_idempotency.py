from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('academy', '0032_pushoutbox'),
    ]

    operations = [
        migrations.AddField(
            model_name='trainingsession',
            name='attendance_revision',
            field=models.PositiveBigIntegerField(default=0),
        ),
        migrations.CreateModel(
            name='AttendanceSubmission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('request_key', models.CharField(max_length=128)),
                ('payload_hash', models.CharField(max_length=64)),
                ('committed_revision', models.PositiveBigIntegerField()),
                ('response_body', models.JSONField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('coach', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='attendance_submissions', to=settings.AUTH_USER_MODEL)),
                ('session', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='attendance_submissions', to='academy.trainingsession')),
            ],
        ),
        migrations.AddConstraint(
            model_name='attendancesubmission',
            constraint=models.UniqueConstraint(fields=('coach', 'request_key'), name='academy_unique_attendance_request'),
        ),
        migrations.AddIndex(
            model_name='attendancesubmission',
            index=models.Index(fields=['session', '-created_at'], name='academy_att_submit_session_idx'),
        ),
    ]
