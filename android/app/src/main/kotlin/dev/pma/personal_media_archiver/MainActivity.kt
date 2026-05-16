package dev.pma.personal_media_archiver

import android.content.Intent
import android.net.Uri
import android.util.Base64
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "PMA-YtDL"
        private const val METHOD_CHANNEL = "dev.pma/ytdl"
        private const val EVENT_CHANNEL = "dev.pma/ytdl_events"
        private const val COOKIES_SHARE_CHANNEL = "dev.pma/cookies_share"
    }

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var eventSink: EventChannel.EventSink? = null
    private var cookiesShareSink: EventChannel.EventSink? = null
    private var ytdlInitialized = false
    private val ytdlInitLock = Any()
    // 緩衝：若 Dart 端還沒 attach EventChannel 就先 buffer 第一筆 share content
    private var pendingCookiesShare: String? = null

    /// 進行中工作 id -> 對應的 cancellation flag。
    /// YoutubeDL.destroyProcessById 可以中斷正在跑的 process。
    private val runningTasks = ConcurrentHashMap<String, Boolean>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(::onMethodCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        // Cookies share intent channel — Firefox 等 app share cookies.txt 過來
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            COOKIES_SHARE_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                cookiesShareSink = events
                // 把 attach 前 buffer 的 share content flush 給 Dart
                pendingCookiesShare?.let {
                    events?.success(it)
                    pendingCookiesShare = null
                }
            }

            override fun onCancel(arguments: Any?) {
                cookiesShareSink = null
            }
        })

        maybeRunAdbTestUrl()
        maybeRunAdbShareCookies(intent)
        // 處理首次 launch 的 share intent
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App 已在 foreground 收到新 share intent
        handleShareIntent(intent)
        // 重新檢查 ADB test hooks（允許重複觸發）
        maybeRunAdbTestUrl()
        maybeRunAdbShareCookies(intent)
    }

    /// Dev/QA hook：ADB 直接餵 base64-encoded cookies content 給 share channel，
    /// 繞過 GUI share intent 的 scoped storage 限制。
    /// 用法：
    ///   B64=$(base64 -i cookies.txt)
    ///   adb shell am start -n dev.pma.personal_media_archiver/.MainActivity \
    ///     --es pma_share_cookies_b64 "$B64"
    /// 只在 debug build 有意義（release 也 enable 但無真實 attack surface
    /// — 攻擊者要能 adb 跑就已 root user device）
    private fun maybeRunAdbShareCookies(intent: Intent?) {
        // Security gate: 同 maybeRunAdbTestUrl — debug only。release 不允許外部 app
        // 透過 ADB-style intent extra 替換 user cookies。
        if (!BuildConfig.DEBUG) return
        if (intent == null) return
        val b64 = intent.getStringExtra("pma_share_cookies_b64")?.takeIf { it.isNotBlank() } ?: return
        try {
            val decoded = String(Base64.decode(b64, Base64.DEFAULT), Charsets.UTF_8)
            Log.i(TAG, "ADB share cookies hook: decoded ${decoded.length} chars; pushing to share channel")
            // 跟 handleShareIntent 同邏輯：if sink attached push 直接，否則 buffer
            ioScope.launch {
                withContext(Dispatchers.Main) {
                    if (cookiesShareSink != null) {
                        cookiesShareSink?.success(decoded)
                    } else {
                        pendingCookiesShare = decoded
                    }
                }
            }
            // 用過即清 — 避免 onResume 重觸發
            intent.removeExtra("pma_share_cookies_b64")
        } catch (e: Throwable) {
            Log.e(TAG, "ADB share cookies hook decode failed", e)
        }
    }

    /// 從 ACTION_SEND intent 取出 cookies 內容 → push 給 Dart side
    /// 支援兩種 payload：
    ///   1. EXTRA_TEXT：文字（Firefox cookies extension 「Copy to clipboard then share」走這條）
    ///   2. EXTRA_STREAM：file Uri（直接 share .txt 檔走這條）
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND) return

        ioScope.launch {
            try {
                val text: String? = intent.getStringExtra(Intent.EXTRA_TEXT)
                val uri: Uri? = @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

                val content: String? = when {
                    !text.isNullOrBlank() -> text
                    uri != null -> readUriAsText(uri)
                    else -> null
                }

                if (content.isNullOrBlank()) {
                    Log.w(TAG, "share intent received but no EXTRA_TEXT or EXTRA_STREAM")
                    return@launch
                }

                // 簡易 heuristic 過濾：必須像 cookies file
                if (!content.contains("# Netscape HTTP Cookie File") &&
                    !content.contains("youtube.com")) {
                    Log.w(TAG, "share content doesn't look like cookies file (len=${content.length})")
                    return@launch
                }

                Log.i(TAG, "received cookies share (len=${content.length}); pushing to Dart")
                withContext(Dispatchers.Main) {
                    if (cookiesShareSink != null) {
                        cookiesShareSink?.success(content)
                    } else {
                        // Dart 還沒 attach EventChannel — buffer 給之後 flush
                        pendingCookiesShare = content
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "handleShareIntent failed", e)
            }
        }
    }

    private fun readUriAsText(uri: Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                BufferedReader(InputStreamReader(input)).use { it.readText() }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "readUriAsText failed for $uri", e)
            null
        }
    }

    /// Dev/QA hook：偵測 intent extra `pma_test_url`，若存在則繞過 UI 直接觸發 yt-dlp 下載
    /// 用法：adb shell am start -n dev.pma.personal_media_archiver/.MainActivity \
    ///       --es pma_test_url "https://youtu.be/jNQXAC9IVRw"
    /// log 看 TAG=PMA-YtDL 結果與檔案路徑
    private fun maybeRunAdbTestUrl() {
        // Security gate: ADB QA hooks are exported via MainActivity (MAIN intent-filter
        // forces android:exported="true"). 任何 app 都能 `am start` 觸發 — release build
        // 必須關掉這 attack surface，只在 debug build 開啟給開發者 ADB e2e 用。
        if (!BuildConfig.DEBUG) return
        val testUrl = intent?.getStringExtra("pma_test_url")?.takeIf { it.isNotBlank() } ?: return
        val cookiesPath = intent?.getStringExtra("pma_cookies_path")?.takeIf { it.isNotBlank() }
        val taskId = "adb-test-${System.currentTimeMillis()}"
        val outDir = (getExternalFilesDir("Movies") ?: filesDir).absolutePath
        Log.i(TAG, "ADB test hook: url=$testUrl taskId=$taskId outDir=$outDir cookies=${cookiesPath ?: "<none>"}")
        download(taskId, testUrl, outDir, false, cookiesPath, object : MethodChannel.Result {
            override fun success(result: Any?) {
                Log.i(TAG, "ADB test SUCCESS: filepath=$result")
            }
            override fun error(code: String, msg: String?, details: Any?) {
                Log.e(TAG, "ADB test ERROR: code=$code msg=$msg")
            }
            override fun notImplemented() {
                Log.w(TAG, "ADB test notImplemented")
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        ioScope.cancel()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initYtdl(result)
            "getInfo" -> getInfo(
                call.argument<String>("url") ?: "",
                call.argument<String>("cookiesPath"),
                result,
            )
            "download" -> {
                val taskId = call.argument<String>("taskId") ?: ""
                val url = call.argument<String>("url") ?: ""
                val outputDir = call.argument<String>("outputDir") ?: ""
                val audioOnly = call.argument<Boolean>("audioOnly") ?: false
                val cookiesPath = call.argument<String>("cookiesPath")
                download(taskId, url, outputDir, audioOnly, cookiesPath, result)
            }
            "cancel" -> {
                val taskId = call.argument<String>("taskId") ?: ""
                cancel(taskId, result)
            }
            "version" -> result.success(safeVersion())
            "update" -> updateYtdlp(result)
            else -> result.notImplemented()
        }
    }

    private fun updateYtdlp(result: MethodChannel.Result) {
        ioScope.launch {
            try {
                ensureInitialized()
                val status = YoutubeDL.getInstance().updateYoutubeDL(
                    applicationContext,
                    YoutubeDL.UpdateChannel._STABLE,
                )
                val version = YoutubeDL.getInstance().versionName(applicationContext)
                    ?: "unknown"
                Log.i(TAG, "updateYoutubeDL status=$status version=$version")
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "status" to status.toString(),
                        "version" to version,
                    ))
                }
            } catch (e: Throwable) {
                Log.e(TAG, "updateYoutubeDL failed", e)
                withContext(Dispatchers.Main) {
                    result.error("UPDATE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun initYtdl(result: MethodChannel.Result) {
        ioScope.launch {
            try {
                ensureInitialized()
                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Throwable) {
                Log.e(TAG, "init failed", e)
                withContext(Dispatchers.Main) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }
        }
    }

    private fun ensureInitialized() {
        if (ytdlInitialized) return
        synchronized(ytdlInitLock) {
            if (ytdlInitialized) return
            try {
                YoutubeDL.getInstance().init(applicationContext)
                FFmpeg.getInstance().init(applicationContext)
                ytdlInitialized = true
                Log.i(TAG, "yt-dlp initialized: ${YoutubeDL.getInstance().versionName(applicationContext)}")
                // 啟動非同步更新；不阻擋首次使用
                ioScope.launch {
                    try {
                        val s = YoutubeDL.getInstance().updateYoutubeDL(
                            applicationContext,
                            YoutubeDL.UpdateChannel._STABLE,
                        )
                        Log.i(TAG, "auto-update result: $s -> ${YoutubeDL.getInstance().versionName(applicationContext)}")
                    } catch (e: Throwable) {
                        Log.w(TAG, "auto-update failed (will use bundled)", e)
                    }
                }
            } catch (e: YoutubeDLException) {
                throw e
            }
        }
    }

    private fun safeVersion(): String {
        return try {
            ensureInitialized()
            YoutubeDL.getInstance().versionName(applicationContext)
                ?: YoutubeDL.getInstance().version(applicationContext)
                ?: "unknown"
        } catch (e: Throwable) {
            "init-error: ${e.message}"
        }
    }

    private fun getInfo(url: String, cookiesPath: String?, result: MethodChannel.Result) {
        if (url.isBlank()) {
            result.error("BAD_ARG", "url is empty", null)
            return
        }
        ioScope.launch {
            try {
                ensureInitialized()
                val req = YoutubeDLRequest(url)
                req.addOption("--no-playlist")
                applySiteSpecificArgs(req, url)
                if (!cookiesPath.isNullOrBlank()) {
                    req.addOption("--cookies", cookiesPath)
                    Log.i(TAG, "getInfo using --cookies $cookiesPath")
                }
                val info: VideoInfo = YoutubeDL.getInstance().getInfo(req)
                val map = HashMap<String, Any?>().apply {
                    put("id", info.id)
                    put("title", info.title)
                    put("uploader", info.uploader)
                    put("duration", info.duration)
                    put("thumbnail", info.thumbnail)
                    put("extractor", info.extractor)
                    put("webpageUrl", info.webpageUrl)
                    put("description", info.description)
                    put("ext", info.ext)
                }
                withContext(Dispatchers.Main) { result.success(map) }
            } catch (e: Throwable) {
                Log.w(TAG, "getInfo failed for $url", e)
                withContext(Dispatchers.Main) {
                    result.error("INFO_FAILED", e.message, null)
                }
            }
        }
    }

    private fun download(
        taskId: String,
        url: String,
        outputDir: String,
        audioOnly: Boolean,
        cookiesPath: String?,
        result: MethodChannel.Result,
    ) {
        if (taskId.isBlank() || url.isBlank() || outputDir.isBlank()) {
            result.error("BAD_ARG", "taskId/url/outputDir required", null)
            return
        }
        runningTasks[taskId] = true

        ioScope.launch {
            try {
                ensureInitialized()
                val dir = File(outputDir)
                if (!dir.exists()) dir.mkdirs()

                val req = YoutubeDLRequest(url)
                req.addOption("--no-playlist")
                req.addOption("--no-mtime")
                applySiteSpecificArgs(req, url)
                if (!cookiesPath.isNullOrBlank()) {
                    req.addOption("--cookies", cookiesPath)
                    Log.i(TAG, "download taskId=$taskId using --cookies $cookiesPath")
                }
                if (audioOnly) {
                    req.addOption("-x")
                    req.addOption("--audio-format", "m4a")
                    req.addOption("-o", "${dir.absolutePath}/%(title)s.%(ext)s")
                } else {
                    req.addOption(
                        "-f",
                        "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                    )
                    req.addOption("--merge-output-format", "mp4")
                    req.addOption("-o", "${dir.absolutePath}/%(title)s.%(ext)s")
                }

                YoutubeDL.getInstance().execute(req, taskId) { progress, etaSec, line ->
                    val payload = mapOf(
                        "taskId" to taskId,
                        "type" to "progress",
                        "progress" to progress.toDouble(),
                        "etaSec" to etaSec,
                        "line" to line,
                    )
                    runOnUiThread { eventSink?.success(payload) }
                }

                runningTasks.remove(taskId)
                val files = listFilesByTaskHint(dir, url)
                val outPath = files.firstOrNull()?.absolutePath ?: ""
                val payload = mapOf(
                    "taskId" to taskId,
                    "type" to "completed",
                    "filepath" to outPath,
                )
                runOnUiThread { eventSink?.success(payload) }
                withContext(Dispatchers.Main) { result.success(outPath) }
            } catch (e: Throwable) {
                runningTasks.remove(taskId)
                val canceled = e.message?.contains("canceled", ignoreCase = true) == true ||
                    e.message?.contains("Aborted", ignoreCase = true) == true
                val payload = mapOf(
                    "taskId" to taskId,
                    "type" to if (canceled) "canceled" else "failed",
                    "error" to (e.message ?: "unknown error"),
                )
                runOnUiThread { eventSink?.success(payload) }
                withContext(Dispatchers.Main) {
                    if (canceled) {
                        result.success(null)
                    } else {
                        result.error("DOWNLOAD_FAILED", e.message, null)
                    }
                }
            }
        }
    }

    private fun cancel(taskId: String, result: MethodChannel.Result) {
        if (taskId.isBlank()) {
            result.error("BAD_ARG", "taskId required", null)
            return
        }
        ioScope.launch {
            try {
                val ok = YoutubeDL.getInstance().destroyProcessById(taskId)
                runningTasks.remove(taskId)
                withContext(Dispatchers.Main) { result.success(ok) }
            } catch (e: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("CANCEL_FAILED", e.message, null)
                }
            }
        }
    }

    /// 對特定站點注入 extractor-args，繞過反爬機制
    ///
    /// YouTube 2024+ 對 yt-dlp 預設的 android_vr/web_safari client 加強 bot 檢測，
    /// 改走 tv → mweb → android_vr → web_safari fallback 鏈以提高成功率。
    /// 參考 https://github.com/yt-dlp/yt-dlp 之 EXTRACTOR ARGUMENTS 章節。
    private fun applySiteSpecificArgs(req: YoutubeDLRequest, url: String) {
        val host = try {
            java.net.URI(url).host?.lowercase() ?: ""
        } catch (_: Throwable) {
            ""
        }
        val isYouTube = host.endsWith("youtube.com") ||
            host.endsWith("youtu.be") ||
            host.endsWith("youtube-nocookie.com") ||
            host.endsWith("music.youtube.com")
        if (isYouTube) {
            req.addOption(
                "--extractor-args",
                "youtube:player_client=tv,mweb,android_vr,web_safari",
            )
        }
    }

    /// 簡單 heuristic：找最近修改的檔案作為下載結果
    private fun listFilesByTaskHint(dir: File, url: String): List<File> {
        if (!dir.isDirectory) return emptyList()
        val cutoff = System.currentTimeMillis() - 10 * 60 * 1000L
        return dir.listFiles()?.toList()
            ?.filter { it.isFile && it.lastModified() >= cutoff }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()
    }
}
