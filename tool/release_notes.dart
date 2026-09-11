// Prints the GitHub release notes for one version, taken from CHANGELOG.md.
//
// Run with `dart`, not `dart run`: the latter prints its build-hook progress to
// stdout, where it would land in the notes file.
//
//   dart tool/release_notes.dart 1.6.3 > notes.md
//   gh release create v1.6.3 <apk> --title v1.6.3 --notes-file notes.md
//
// The release notes are the changelog entry and nothing else, followed by a
// link to the full diff, so the two cannot say different things.

import 'dart:io';

const repository = 'https://github.com/SahilK-027/Deltoid';

/// A released version's heading: `## [1.6.3] - 2026-09-11`.
final releaseHeading = RegExp(r'^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})$');

/// Every released version in [changelog], newest first.
List<String> releasedVersions(String changelog) => [
      for (final line in changelog.split('\n'))
        if (releaseHeading.firstMatch(line) case final m?) m.group(1)!,
    ];

/// The body of [version]'s entry: everything under its heading, up to the next
/// release heading or the link references.
String entryBody(String changelog, String version) {
  final lines = changelog.split('\n');
  final start = lines.indexWhere(
    (l) => releaseHeading.firstMatch(l)?.group(1) == version,
  );
  if (start == -1) {
    throw ArgumentError('CHANGELOG.md has no entry for $version');
  }
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ') || line.startsWith('[')) break;
    body.add(line);
  }
  return body.join('\n').trim();
}

/// The release notes for [version]: its entry, and a link to the full diff
/// from the version before it.
String releaseNotes(String changelog, String version) {
  final versions = releasedVersions(changelog);
  final index = versions.indexOf(version);
  final previous = index + 1 < versions.length ? versions[index + 1] : null;
  final link = previous == null
      ? '$repository/commits/v$version'
      : '$repository/compare/v$previous...v$version';
  return '${entryBody(changelog, version)}\n\n**Full changelog:** $link\n';
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/release_notes.dart <version>');
    exit(64);
  }
  stdout.write(releaseNotes(File('CHANGELOG.md').readAsStringSync(), args[0]));
}
