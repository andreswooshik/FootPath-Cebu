import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain depends only on Dart and other domain code', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib/domain',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final directive in RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(file.readAsStringSync())) {
        final uri = directive.group(1)!;
        final allowed =
            uri.startsWith('package:footpath_cebu/domain/') ||
            const {
              'dart:async',
              'dart:collection',
              'dart:convert',
              'dart:math',
              'dart:typed_data',
            }.contains(uri);
        if (!allowed) violations.add('${file.path}: $uri');
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Domain rules must remain independent of UI and infrastructure.',
    );
  });

  test('migrated domain entities do not own wire serialization', () {
    for (final path in [
      'lib/domain/entities/app_notification.dart',
      'lib/domain/entities/dispute.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('fromJson')), reason: path);
      expect(source, isNot(contains('toJson')), reason: path);
      expect(source, isNot(contains("['")), reason: path);
    }
  });

  test(
    'presentation does not import concrete data adapters or platform services',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib/presentation',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final directive in RegExp(
          r'''(?:import|export)\s+['"]([^'"]+)['"]''',
        ).allMatches(file.readAsStringSync())) {
          final uri = directive.group(1)!;
          if (uri.contains('/data/') ||
              uri.startsWith('package:http/') ||
              uri.startsWith('package:firebase_') ||
              uri.startsWith('package:sqflite')) {
            violations.add('${file.path}: $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Resolve infrastructure through domain contracts and the composition root.',
      );
    },
  );
}
