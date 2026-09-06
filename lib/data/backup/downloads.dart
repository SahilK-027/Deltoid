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
      'Saving to Downloads is not available on this device.',
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
      'Saving to Downloads is not available on this device. '
      'Use Share instead.',
    );
  }
}

/// Asks the system picker for a backup and returns a **file on disk**, or null
/// if the picker was dismissed.
///
/// The platform copies the chosen document into the app's cache and hands back
/// a path. `file_selector` hands back the contents instead, and a long history
/// killed the process on the way through the codec — a 67 MB file is a 134 MB
/// array on the main thread, thrown before the restore had written a row. The
/// export side has always avoided that (see [saveToDownloads]); this is the
/// same rule inbound, and it means the file can then be read a chunk at a time.
///
/// Falls back to [fallback] where the channel is not implemented, so a build
/// without the host code still restores small files rather than nothing.
Future<File?> pickBackupFile({
  Future<File?> Function()? fallback,
}) async {
  if (!canSaveToDownloads) return fallback?.call();
  try {
    final path = await _channel.invokeMethod<String>('pickBackup');
    return path == null ? null : File(path);
  } on PlatformException catch (e) {
    throw BackupSaveException(e.message ?? 'That file could not be opened.');
  } on MissingPluginException {
    return fallback?.call();
  }
}

class BackupSaveException implements Exception {
  const BackupSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
