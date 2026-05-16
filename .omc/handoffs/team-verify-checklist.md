# Verify Checklist (team-verify stage)

Lead reads this after team-exec completes to spawn verifier + reviewers.

## Quality gates (all must pass)

- [ ] `fvm flutter analyze` — 0 error, 0 warning（baseline 是 0 issue）
- [ ] `fvm flutter test test/` — 全部測試 PASS（baseline 12 個 + W4 新加 ≥3 個 = 15+）
- [ ] `fvm flutter build apk --debug` — exit code 0，APK ~250MB

## Wiring 完整性（W3 範圍）

- [ ] MainActivity.kt `download()` 收到 cookiesPath 非空時加 `req.addOption("--cookies", path)`
- [ ] MainActivity.kt `getInfo()` 同上
- [ ] MainActivity.kt `maybeRunAdbTestUrl` 從 `intent.getStringExtra("pma_cookies_path")` 讀路徑並傳入 download
- [ ] `YtDlpBridge.download/getInfo` 支援 `String? cookiesPath` 參數，invokeMethod params 帶 cookiesPath
- [ ] `task_controller._runYtDlp` 與 getInfo 取得 cookiesPath 透過 ref.read(cookiesServiceProvider).path() 並傳遞
- [ ] `_humanize` 偵測 "Sign in to confirm" / "cookies-from-browser" → return 帶 `[NEEDS_COOKIES] ` prefix 訊息
- [ ] `DownloadTask.needsCookies` getter 從 errorMessage 推斷

## UI 完整性（W2 範圍）

- [ ] 設定頁有「進階」section，位於「關於」之上
- [ ] 「YouTube cookies」ListTile 三態正確：未匯入 / 已匯入 (顯示 domain count + import time) / 載入中
- [ ] 匯入流程：FilePicker → CookiesService.import → SnackBar 成功 / 失敗
- [ ] 已匯入時 PopupMenuButton 有「重新匯入」「刪除」
- [ ] pubspec.yaml 加 file_picker，`fvm flutter pub get` exit 0

## Storage 完整性（W1 範圍）

- [ ] CookiesService.import 驗證 Netscape header（第一行 `# Netscape HTTP Cookie File` 或開頭 200 chars 包含）
- [ ] 驗證至少一行有 youtube.com / .youtube.com domain
- [ ] copy 到 `<docs>/ytdlp/youtube.cookies.txt`，mkdirs OK
- [ ] CookiesService.exists / path / remove / meta 都 work
- [ ] cookiesServiceProvider 註冊在 providers.dart

## 文檔（W4 範圍 Part 1）

- [ ] README 「YouTube cookies 取得步驟」教學完整（chrome extension Get cookies.txt LOCALLY、export、推到 device、匯入）
- [ ] cookies_service_test.dart 至少 3 個 test：valid Netscape、no youtube domain reject、bad header reject

## 真機 e2e（W4 範圍 Part 2 — 最關鍵）

- [ ] Note 9 (25c027b4fe1c7ece) 安裝最新 debug APK 成功
- [ ] `/sdcard/Download/fake_yt_cookies.txt` push 成功
- [ ] `am start ... --es pma_cookies_path /sdcard/Download/fake_yt_cookies.txt --es pma_test_url https://youtu.be/jNQXAC9IVRw` 啟動
- [ ] logcat 出現 `--cookies` flag 或 cookies path 訊號（證明 W3 wiring 成功）
- [ ] 即使 yt-dlp 仍回 bot challenge（fake cookies 預期）也 OK — 整合鏈通就是 verify PASS
- [ ] `.omc/autopilot/yt-cookies-verification.md` 寫好

## Verifier 角色

Verify 階段呼叫 `oh-my-claudecode:verifier` agent，給它本 checklist 跟相關 files，要求 evidence-based 回答每個 checkbox 是否 PASS。

如有 FAIL → 進 team-fix loop（最多 max_fix_loops=3），spawn debugger 或補丁 executor 修。
