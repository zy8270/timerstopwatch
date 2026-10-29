package com.timerstopwatch.timerstopwatch

import android.content.Context
import io.flutter.FlutterInjector
import java.io.File

/**
 * 考试模式音频：随 APK 打包在 Flutter assets（audio/），首次调用时拷贝到
 * 应用私有目录并返回绝对路径，供 AlarmRing 按文件路径播放。
 * 固定文件名 + 每次覆盖写入：应用更新换音频后自动生效。
 */
object ExamAudio {

    private val entries = listOf(
        "start" to Triple("audio/start.m4a", "exam_start.m4a", "audio_start"),
        "mid15" to Triple("audio/15min.m4a", "exam_15min.m4a", "audio_15min"),
        "end" to Triple("audio/end.m4a", "exam_end.m4a", "audio_end")
    )

    /** 返回 key → 私有目录绝对路径；assets 缺失的条目跳过（Dart 侧回退系统提示音）。 */
    fun ensure(context: Context): Map<String, String> {
        val ctx = context.applicationContext
        val dir = File(ctx.filesDir, "audio").apply { mkdirs() }
        val loader = FlutterInjector.instance().flutterLoader()
        val out = mutableMapOf<String, String>()
        for ((key, spec) in entries) {
            val (asset, saveName, logTag) = spec
            val target = File(dir, saveName)
            runCatching {
                ctx.assets.open(loader.getLookupKeyForAsset(asset)).use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                out[key] = target.absolutePath
            }.onFailure {
                android.util.Log.w("ExamAudio", "copy $logTag failed", it)
            }
        }
        return out
    }
}
