import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_notes.dart';

/// CHANGELOG.md follows one template, described in its own header, so every
/// entry — and every GitHub release built from one — reads the same way.
///
/// Before this test the entries were written freehand: some wrapped at eighty
/// columns and some not, which GitHub renders as line breaks in one release
/// and flowing text in the next, and each chose its own headings and depth.
void main() {
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final lines = changelog.split('\n');

  const sections = [
    'Added',
    'Changed',
    'Deprecated',
    'Removed',
    'Fixed',
    'Security',
    'Internal',
    'Upgrade notes',
  ];
  const areaSections = {
    'Added',
    'Changed',
    'Deprecated',
    'Removed',
    'Fixed',
    'Security',
  };

  /// Each release's lines, keyed by version.
  Map<String, List<String>> entries() {
    final out = <String, List<String>>{};
    List<String>? current;
    for (final line in lines) {
      if (line.startsWith('## ')) {
        final m = releaseHeading.firstMatch(line);
        current = m == null ? null : (out[m.group(1)!] = []);
        continue;
      }
      if (line.startsWith('[')) current = null;
      current?.add(line);
    }
    return out;
  }

  test('every level-two heading is a release or Unreleased', () {
    for (final line in lines.where((l) => l.startsWith('## '))) {
      expect(
        line == '## [Unreleased]' || releaseHeading.hasMatch(line),
        isTrue,
        reason: 'expected `## [x.y.z] - YYYY-MM-DD`, found `$line`',
      );
    }
  });

  test('releases run newest first, with dates that never go forwards', () {
    final dated = [
      for (final line in lines)
        if (releaseHeading.firstMatch(line) case final m?)
          (version: m.group(1)!, date: m.group(2)!),
    ];
    for (var i = 1; i < dated.length; i++) {
      final newer = dated[i - 1].version.split('.').map(int.parse).toList();
      final older = dated[i].version.split('.').map(int.parse).toList();
      final compare = newer[0] != older[0]
          ? newer[0] - older[0]
          : newer[1] != older[1]
              ? newer[1] - older[1]
              : newer[2] - older[2];
      expect(compare, greaterThan(0),
          reason: '${dated[i - 1].version} is listed above ${dated[i].version}');
      expect(dated[i - 1].date.compareTo(dated[i].date), greaterThanOrEqualTo(0),
          reason: '${dated[i - 1].version} is dated before ${dated[i].version}');
    }
  });

  test('the newest release is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version: (\d+\.\d+\.\d+)\+\d+$', multiLine: true)
        .firstMatch(pubspec)!
        .group(1);
    expect(releasedVersions(changelog).first, version);
  });

  test('each entry opens with a summary, then known sections in order', () {
    entries().forEach((version, body) {
      final content = body.where((l) => l.isNotEmpty).toList();
      expect(content, isNotEmpty, reason: '$version is empty');
      expect(content.first,
          allOf(isNot(startsWith('#')), isNot(startsWith('-'))),
          reason: '$version must open with a one-line summary');
      expect(content.first, matches(RegExp(r'^(Initial|Patch|Minor|Major) ')),
          reason: '$version: the summary names the release type');

      var last = -1;
      for (final line in content.where((l) => l.startsWith('#'))) {
        expect(line, startsWith('### '),
            reason: '$version: `$line` is not a section heading');
        final name = line.substring(4);
        final index = sections.indexOf(name);
        expect(index, isNot(-1), reason: '$version: unknown section `$name`');
        expect(index, greaterThan(last),
            reason: '$version: `$name` is out of order or repeated');
        last = index;
      }
      expect(last, isNot(-1), reason: '$version has no sections');
    });
  });

  test('user-facing bullets open with their area', () {
    final area = RegExp(r'^- \*\*[A-Z][A-Za-z ]*:\*\* \S');
    entries().forEach((version, body) {
      String? section;
      for (final line in body) {
        if (line.startsWith('### ')) section = line.substring(4);
        if (!line.startsWith('- ')) continue;
        if (areaSections.contains(section)) {
          expect(line, matches(area),
              reason: '$version › $section: `$line` has no `**Area:**` prefix');
        }
      }
    });
  });

  test('one line per paragraph and per bullet, with no hard wrapping', () {
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final previous = lines[i - 1];
      if (line.isEmpty || previous.isEmpty) continue;
      final opensBlock = line.startsWith('#') ||
          line.startsWith('- ') ||
          line.startsWith('  - ') ||
          line.startsWith('[');
      expect(opensBlock, isTrue,
          reason: 'line ${i + 1} continues the line above it: `$line`');
      if (line.startsWith('  - ')) {
        expect(previous, anyOf(startsWith('- '), startsWith('  - ')),
            reason: 'line ${i + 1} is a nested bullet with no parent');
      }
    }
  });

  test('blocks are separated by exactly one blank line', () {
    expect(changelog, endsWith('\n'));
    expect(changelog, isNot(endsWith('\n\n')));
    expect(changelog, isNot(contains('\n\n\n')),
        reason: 'two blank lines in a row');
    for (var i = 1; i < lines.length; i++) {
      if (!lines[i].startsWith('#')) continue;
      expect(lines[i - 1], isEmpty,
          reason: 'line ${i + 1}: a heading needs a blank line above it');
      if (i + 1 < lines.length) {
        expect(lines[i + 1], isEmpty,
            reason: 'line ${i + 1}: a heading needs a blank line below it');
      }
    }
  });

  test('every release has a link reference, and nothing else does', () {
    final versions = releasedVersions(changelog);
    final references = {
      for (final line in lines)
        if (RegExp(r'^\[([^\]]+)\]: (\S+)$').firstMatch(line) case final m?)
          m.group(1)!: m.group(2)!,
    };
    expect(references['Unreleased'],
        '$repository/compare/v${versions.first}...HEAD');
    for (var i = 0; i < versions.length; i++) {
      final v = versions[i];
      final expected = i + 1 < versions.length
          ? '$repository/compare/v${versions[i + 1]}...v$v'
          : '$repository/releases/tag/v$v';
      expect(references[v], expected, reason: 'link reference for $v');
    }
    expect(references.length, versions.length + 1,
        reason: 'a link reference with no release');
  });

  test('no exclamation marks', () {
    expect(changelog, isNot(contains('!')));
  });

  test('release notes are the entry plus a link to the diff', () {
    final notes = releaseNotes(changelog, '1.6.2');
    expect(notes, startsWith('Patch release'));
    expect(notes, isNot(contains('## [')));
    expect(notes, endsWith('**Full changelog:** '
        '$repository/compare/v1.6.1...v1.6.2\n'));
  });
}
