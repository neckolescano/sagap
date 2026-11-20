package dev.sagap.sagap

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * `sagap/share`: hands a report image to Android's share sheet (SPEC.md §9).
 *
 * The image is written to the app's private cache (`cache/reports/`) and
 * exposed only through a [FileProvider] URI with a one-time read grant.
 * Older reports are deleted first, so at most one stays on the phone.
 * Sagap uploads nothing; the user picks the receiving app.
 */
class ShareHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "sagap/share"
        private const val REPORTS_DIR = "reports"
        private const val AUTHORITY_SUFFIX = ".reports"
        private const val MIME_PNG = "image/png"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareImage" -> shareImage(call, result)
            else -> result.notImplemented()
        }
    }

    private fun shareImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank() ||
            fileName.contains('/') || !fileName.endsWith(".png")
        ) {
            result.error("bad_args", "Expected PNG bytes and a plain .png file name", null)
            return
        }
        val file = try {
            val dir = File(activity.cacheDir, REPORTS_DIR)
            if (!dir.exists() && !dir.mkdirs()) throw IOException("Could not create $dir")
            dir.listFiles()?.forEach { it.delete() }
            File(dir, fileName).apply { writeBytes(bytes) }
        } catch (e: IOException) {
            result.error("write_failed", "Could not save the report: ${e.message}", null)
            return
        }
        val uri = FileProvider.getUriForFile(
            activity,
            activity.packageName + AUTHORITY_SUFFIX,
            file,
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = MIME_PNG
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(Intent.createChooser(send, "Share report"))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_app", "No app on this phone can receive an image", null)
        }
    }
}
