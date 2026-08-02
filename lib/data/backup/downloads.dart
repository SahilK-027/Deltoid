import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// The folder backups land in, inside the phone's Downloads.
const downloadsFolder = 'Deltoid_Backup';

const _channel = MethodChannel('com.deltoid.deltoid/files');

/// Whether "save to Downloads" can be offered at all.
bool get canSaveToDownloads => !kIsWeb && Platform.isAndroid;

/// Copies [file] into `Downloads/Deltoid_Backup`, returning where it landed.
///
/// The share sheet was the only way out of the app, and sharing a backup to
/// yourself is a strange thing to have to do — every other app that produces a
/// file puts it in Downloads. The copy is made on the platform side straight
/// from the path, so a decade of training does not cross a method channel as
/// one string.
///
/// Throws [BackupSaveException] when the platform refuses; the caller says so
/// rather than reporting a save that did not happen.
Future<String> saveToDownloads(File file) async {
  if (!canSaveToDownloads) {
    throw const BackupSaveException(
      'Saving to Downloads is only available on Android.',
    );
  }
  try {
    final location = await _channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': file.path,
      'fileName': file.uri.pathSegments.last,
      'folder': downloadsFolder,
    });
    return location ?? '$downloadsFolder/${file.uri.pathSegments.last}';
  } on PlatformException catch (e) {
    throw BackupSaveException(e.message ?? 'The file could not be saved.');
  } on MissingPluginException {
    throw const BackupSaveException(
      'This build cannot write to Downloads. Use Share instead.',
    );
  }
}

class BackupSaveException implements Exception {
  const BackupSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
