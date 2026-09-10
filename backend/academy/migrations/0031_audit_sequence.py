"""Preserve historical v1 proofs; all new entries use a sequenced v2 digest."""

from django.db import migrations, models


def sequence_existing(apps, schema_editor):
    audit = apps.get_model('academy', 'AuditLog')
    for sequence, entry in enumerate(audit.objects.using(schema_editor.connection.alias).order_by('created_at', 'id').iterator(), 1):
        audit.objects.using(schema_editor.connection.alias).filter(pk=entry.pk).update(
            sequence=sequence,
            actor_identifier=str(entry.actor_id) if entry.actor_id else '',
        )


class Migration(migrations.Migration):
    dependencies = [('academy', '0030_auditlog_entry_hash_auditlog_previous_hash_and_more')]
    operations = [
        migrations.AddField('auditlog', 'sequence', models.PositiveBigIntegerField(null=True, editable=False, unique=True)),
        migrations.AddField('auditlog', 'hash_version', models.PositiveSmallIntegerField(default=1, editable=False)),
        migrations.AddField('auditlog', 'actor_identifier', models.CharField(max_length=64, blank=True, editable=False)),
        migrations.RunPython(sequence_existing, migrations.RunPython.noop),
        migrations.AlterField('auditlog', 'sequence', models.PositiveBigIntegerField(editable=False, unique=True)),
        migrations.AlterField('auditlog', 'hash_version', models.PositiveSmallIntegerField(default=2, editable=False)),
    ]
