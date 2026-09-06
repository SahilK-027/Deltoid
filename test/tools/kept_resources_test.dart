import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every Android resource this app names from Dart is kept, by name, in
/// `res/raw/keep.xml`.**
///
/// The release build shrinks resources, and the shrinker keeps what it can see
/// referenced from Java or XML. A resource named only as a string passed to a
/// plugin is invisible to it and is deleted — silently, in release only, on a
/// build nobody runs before shipping it.
///
/// It had already happened twice by the time anything checked. `rest_done`, the
/// tone the OS plays when a rest ends, was missing from every release APK ever
/// built: the alert was silent on a phone in a pocket while the in-app tone —
/// a Flutter asset, which the shrinker never touches — played fine with the app
/// open, which reads as "background notifications are broken" and sent the
/// search a long way from the cause. Then `ic_stat_deltoid` went the same way,
/// and a notification whose icon resource does not exist cannot be posted at
/// all, so the session line vanished with it.
///
/// The failure is invisible three times over: only in release, only on a phone,
/// and behind a `catch` that must swallow it. So it is checked here instead,
/// against the two files that have to agree.
void main() {
  test('every resource named from Dart survives the release shrinker', () {
    final keep = File('android/app/src/main/res/raw/keep.xml');
    expect(
      keep.existsSync(),
      isTrue,
      reason: 'res/raw/keep.xml is what stops the shrinker taking these.',
    );
    final kept = keep.readAsStringSync();

    // Two shapes, because there are two ways this app names a resource: a
    // `@type/name` string handed to flutter_local_notifications, and a raw
    // resource named bare in `RawResourceAndroidNotificationSound`.
    final named = <String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final m in RegExp(r'@(drawable|raw|mipmap)/(\w+)').allMatches(source)) {
        named.add('@${m[1]}/${m[2]}');
      }
      for (final m in RegExp(
        r"RawResourceAndroidNotificationSound\(\s*'(\w+)'",
      ).allMatches(source)) {
        named.add('@raw/${m[1]}');
      }
    }

    expect(
      named,
      isNotEmpty,
      reason: 'The scan found nothing, so it is no longer scanning anything.',
    );

    for (final resource in named) {
      // `@mipmap/ic_launcher` is named in the manifest as the application's
      // icon, so the shrinker can see it and it needs no entry. Everything
      // else has to be listed.
      if (resource == '@mipmap/ic_launcher') continue;
      expect(
        kept.contains(resource),
        isTrue,
        reason:
            '$resource is named from Dart and is not in keep.xml. The release '
            'build will delete it, and the failure will only appear on a '
            'phone: a missing tone plays nothing, a missing icon takes the '
            'whole notification down.',
      );
    }
  });

  test('the resources keep.xml names are actually there', () {
    // The other direction: a kept name that no longer matches a file is a
    // renamed asset, and the rename would take the resource with it.
    final kept = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    final res = Directory('android/app/src/main/res');
    final files = res
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.split('.').first)
        .toSet();

    for (final m in RegExp(r'@(drawable|raw|mipmap)/(\w+)').allMatches(kept)) {
      expect(
        files,
        contains(m[2]),
        reason: 'keep.xml holds ${m[0]} open and no such resource exists.',
      );
    }
  });
}
