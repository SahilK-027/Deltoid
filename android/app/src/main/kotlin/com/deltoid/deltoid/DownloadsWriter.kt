package com.deltoid.deltoid

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Copies a file the app already wrote into the shared Downloads collection,
 * under a folder of our own.
 *
 * App-private external storage is where backups live day to day: it needs no
 * permission and survives reboots. It is also somewhere most file managers
 * will not show you, and a backup you cannot find is one you have to take on
 * faith — so "save to Downloads" puts a copy where the user already looks for
 * downloaded things.
 *
 * Two paths, because shared storage changed shape in Android 10:
 *
 * * **API 29+** — MediaStore owns the collection. Insert a pending row, stream
 *   into the URI it hands back, then clear the pending flag so the file becomes
 *   visible only once it is whole. No permission is involved at all.
 * * **API 28 and below** — the public Downloads directory is a real path, and
 *   writing to it needs `WRITE_EXTERNAL_STORAGE`, which the manifest declares
 *   with `maxSdkVersion="28"`. If it was not granted the write throws, and the
 *   Dart side reports that rather than pretending a copy exists.
 *
 * The file is streamed from a path rather than handed over as bytes: a decade
 * of training is tens of megabytes, and sending that through a method channel
 * copies it twice for no reason.
 */
object DownloadsWriter {

    /** Returns the user-facing location of the copy. */
    fun save(context: Context, sourcePath: String, fileName: String, folder: String): String {
        val source = File(sourcePath)
        if (!source.exists()) throw IllegalArgumentException("No file at $sourcePath")

        val relative = "${Environment.DIRECTORY_DOWNLOADS}/$folder"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeTypeOf(fileName))
                put(MediaStore.Downloads.RELATIVE_PATH, relative)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Downloads rejected the file")

            try {
                resolver.openOutputStream(uri).use { out ->
                    checkNotNull(out) { "Downloads gave no stream to write to" }
                    source.inputStream().use { it.copyTo(out) }
                }
            } catch (e: Exception) {
                // A half-written pending row is invisible but real; drop it so a
                // failed save leaves nothing behind.
                resolver.delete(uri, null, null)
                throw e
            }

            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null,
            )
            return "$relative/$fileName"
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            folder,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create $relative")
        }
        val target = File(dir, fileName)
        source.copyTo(target, overwrite = true)
        return target.absolutePath
    }

    /**
     * The type MediaStore files the copy under, read off its name.
     *
     * MediaStore appends the extension it expects for the type it is given, so
     * a spreadsheet export filed as `application/json` arrived in Downloads as
     * `deltoid-sets-….csv.json`, which no spreadsheet offers to open.
     */
    private fun mimeTypeOf(fileName: String): String = when {
        fileName.endsWith(".csv") -> "text/csv"
        else -> "application/json"
    }
}
