from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('accounts', '0010_coordinator_player_registration'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='middle_initial',
            field=models.CharField(blank=True, default='', max_length=1, null=True),
        ),
        migrations.CreateModel(
            name='MemberRegistration',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('request_key', models.UUIDField()),
                ('payload_hash', models.CharField(max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('coordinator', models.ForeignKey(on_delete=models.deletion.PROTECT, related_name='member_registrations', to='accounts.user')),
                ('member', models.OneToOneField(on_delete=models.deletion.PROTECT, related_name='member_registration', to='accounts.user')),
            ],
        ),
        migrations.AddConstraint(
            model_name='memberregistration',
            constraint=models.UniqueConstraint(fields=('coordinator', 'request_key'), name='unique_member_registration_request'),
        ),
    ]
