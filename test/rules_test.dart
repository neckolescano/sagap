import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Project rules checked against the source (SPEC.md §13).
void main() {
  test('AT21: no user-facing "boost" wording in lib/', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final (i, line) in file.readAsLinesSync().indexed) {
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        if (code.toLowerCase().contains('boost')) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'Sagap measures and advises; it never boosts');
  });

  test('AT22: release (main) manifest does not request INTERNET', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });

  test('no SSID/BSSID reaches Dart: Kotlin never puts them in a result', () {
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'));
    for (final file in kotlin) {
      for (final line in file.readAsLinesSync()) {
        final putsKey = RegExp(r'"(ssid|bssid|SSID|BSSID)"\s+to|\["(ssid|bssid)"\]');
        expect(putsKey.hasMatch(line), isFalse, reason: '${file.path}: $line');
      }
    }
  });
}
