package com.pixel.photostamp

import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    init {
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val dir = File(
                    Environment.getExternalStorageDirectory(),
                    "PhotoStamp"
                )
                if (!dir.exists()) dir.mkdirs()
                val log = File(dir, "native_crash.log")
                val sw = java.io.StringWriter()
                throwable.printStackTrace(java.io.PrintWriter(sw))
                val entry = "[${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(java.util.Date())}]\n$sw\n" + "=".repeat(40) + "\n"
                val fos = FileOutputStream(log, true)
                fos.write(entry.toByteArray())
                fos.close()
            } catch (_: Exception) {
            }
        }
    }
}
