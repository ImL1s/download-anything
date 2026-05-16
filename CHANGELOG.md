# Changelog

All notable changes to PMA are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — 2026-05-16 (round 3: share-URL auto-detect + LICENSE)

### Added — Round 3
- **Android share intent 第二條 channel — share_url**：其他 app（YouTube/Twitter/Chrome）分享 link → PMA 自動分類
  - `MainActivity.kt` 加 `SHARE_URL_CHANNEL` + `shareUrlSink` + `pendingShareUrl` ArrayDeque（修 cold-start 多 share 漏失）
  - `handleShareIntent` 用 heuristic 路由：Netscape cookies signature → cookies channel，其餘 URL → share_url channel
  - `isLikelySingleUrl` 防呆：len ≤ 2048、單 token、http(s)://、URI.parse host 非空
  - 安全 gate：ADB QA hook（pma_test_url / pma_share_cookies_b64 / pma_cookies_path）改用 `ApplicationInfo.FLAG_DEBUGGABLE` 判定，release APK 不開放
- **WARN 共識流程**：政策判 WARN 時不自動下載 — 預填 URL 到首頁 textfield + 切首頁 tab + orange SnackBar 提示，user 看完整 URL + policy banner 後自行決定
  - 新 provider `pendingShareUrlForReviewProvider`（main_shell 寫 / home_page 讀後 clear）
- **Pure handler 抽出**：`lib/state/share_url_handler.dart`
  - `classifyShare(url, policy)` → sealed `ShareUrlAction { Blocked, NeedsConsent, AutoEnqueue }`
  - `isLikelyShareUrl(content)` Dart side mirror，與 Kotlin native 對齊
- **新 unit tests（13 個）**：`test/share_url_handler_test.dart` — URL heuristic 6 cases + 政策對映 7 cases（ALLOW/BLOCK/WARN/strict）
- **Codex stop-review-gate hook**：commit 前自動 ALLOW/BLOCK 評審（Top 3 issues 列表）
- **LICENSE 檔**：補 Apache-2.0 全文 + GPL-3.0 散布說明（修 GitHub 偵測 `NOASSERTION` 問題）

### Changed — Round 3
- `main_shell.dart` 從 inline switch 改用 sealed `ShareUrlAction` switch — 邏輯與展示分離
- `task_controller.dart` cookies 路徑套用：加 `_isYouTubeUrl(url)` host gate，僅 youtube.com / youtu.be / youtube-nocookie.com 才傳 `--cookies` 給 yt-dlp（codex round 1 #1）
- `cookies_service.dart`：`importFromContent` + `meta` 補 `#HttpOnly_` prefix 處理（codex round 1 #2）— 不再把 HttpOnly cookies 行誤判為註解

### Verified — Round 3
- ✅ `fvm flutter analyze` 0 issue
- ✅ `fvm flutter test` 68 tests pass（53 → +2 cookies HttpOnly + 13 share_url_handler）
- ✅ `fvm flutter build apk --debug` 成功
- ✅ Note 9 真機 e2e PASS — share URL 三條路徑（ALLOW 自動 enqueue / WARN 預填 / BLOCK SnackBar）皆驗 + 失敗 task 顯示「匯入 cookies」按鈕

---

## [Unreleased] — 2026-05-16 (round 2: Firefox share intent)

### Added — Round 2
- **方案 B 純手機智慧匯入**：設定 → 進階 → YouTube cookies → 「+」→ 「智慧匯入」
  - PopupMenuButton 兩選項：「智慧匯入（用 Firefox 推薦）」/「從檔案匯入（已有 cookies.txt）」
  - 3-step onboarding dialog 引導 user（ui-ux-pro 等級設計：globe icon + numbered badges + funnel pattern + Atkinson Hyperlegible 繁中）
  - 點「開始」用 `url_launcher` launchUrl `https://www.youtube.com` mode `externalApplication`（Android chooser 讓 user 選 Firefox）
- **Android share intent receiver**：Firefox cookies extension → 「分享」→ PMA → 自動匯入
  - `AndroidManifest.xml` 擴展 `<intent-filter>` 接 `ACTION_SEND` text/* + application/octet-stream + */*
  - `MainActivity.kt` 加 `handleShareIntent`（讀 `EXTRA_TEXT` / `EXTRA_STREAM` Uri）+ `onNewIntent` + 新 EventChannel `dev.pma/cookies_share`
  - `cookies_service.dart` 加 `importFromContent(String)` method（不需 File API）
  - `providers.dart` 加 `cookiesShareStreamProvider` StreamProvider 監聽 native channel
  - `main_shell.dart` 加 `ref.listen` 自動 `CookiesService.importFromContent` + SnackBar 通知（綠色「已自動匯入」/ 紅色失敗訊息）
- **README 方案 B 完整教學**：3 步驟 + 為何選 Firefox（Chrome 2024/07 app-bound encryption + 行動版不支援 extension）
- **新 unit test**：`importFromContent works without File`、`importFromContent rejects invalid content`

### Changed — Round 2
- 設定頁 cookies tile 未匯入態 trailing 從 FilledButton「匯入」變 PopupMenuButton 兩選項（同時提供智慧匯入 + 檔案匯入）
- `main_shell.dart` 加 cookies share auto-import listener — 整個 app 任何時候收到 share intent 都會處理

### Bug Fix — Round 2
- N/A

### Verified
- ✅ `fvm flutter analyze` 0 issue
- ✅ `fvm flutter test` 53 tests pass (baseline 50 + 2 importFromContent + 1 widget test 重命名)
- ✅ `fvm flutter build apk --debug` 成功
- ✅ Note 9 真機 e2e PASS — settings PopupMenuButton + onboarding dialog UI 完整渲染（截圖在 `.omc/autopilot/`）
- ⏳ Firefox share intent 真實 e2e 需 user 在 Note 9 裝 Firefox + cookies extension（無法 lead 自動化驗證）



### Added
- **YouTube cookies 手動匯入**：設定 → 進階 → YouTube cookies → FilePicker 選 Netscape cookies.txt → 儲存至 app private dir
  - `lib/core/cookies/cookies_service.dart`：CookiesService + CookiesMeta + CookiesValidationException
  - `lib/state/providers.dart`：`cookiesServiceProvider`、`cookiesExistsProvider`、`selectedTabProvider`
  - Native bridge：MainActivity.kt 的 `download()` / `getInfo()` 加 `cookiesPath: String?` 參數，套 `--cookies <path>` 給 yt-dlp
  - ADB QA hook：`adb am start --es pma_cookies_path /sdcard/...` 也支援
- **失敗 task「匯入 cookies」按鈕**：當 `task.needsCookies` 為真時，task_card 顯示按鈕點擊跳設定 tab
- **YouTube + 未匯入 cookies hint**：home_page 偵測 YouTube URL 且未匯入 cookies 顯示提示卡片 + 「前往設定」按鈕
- **Cookies 過期偵測**：CookiesService.isExpiring()（>150 天）；settings 顯示「⚠️ 已超過 5 個月，建議重新匯入」
- **媒體庫 sort + filter**：search bar（即時 filter title/filename） + PopupMenuButton 排序（時間新→舊/舊→新、檔名、大小）
- **設定頁開源授權頁**：showLicensePage 列所有依賴授權
- **政策 BLOCK 名單補台灣 OTT**：Hami Video、Catchplay、Viu、Vidol、Pubu、BookWalker、iqiyi.com.tw、MOD
- **新單元測試 / widget test**：
  - `test/cookies_service_test.dart` (5 tests)
  - `test/task_controller_humanize_test.dart` (8 tests)
  - `test/download_task_test.dart` (17 tests)
  - `test/settings_page_cookies_widget_test.dart` (3 widget tests)
  - `test/widget_test.dart` 加 OTT BLOCK 集中 test (9 URL)

### Changed
- `lib/state/task_controller.dart`：`_humanize()` 改 wrap top-level `humanizeYtDlpError()`（方便 unit test），加 `[NEEDS_COOKIES]` prefix 對應 YouTube bot challenge 訊息
- `lib/ui/pages/main_shell.dart`：ConsumerStatefulWidget → ConsumerWidget，用 `selectedTabProvider` 控 tab（讓其他頁面可程式化切 tab）
- `lib/ui/widgets/task_card.dart`：StatelessWidget → ConsumerWidget，加 `needsCookies` 顯示分支
- `lib/core/extractors/ytdlp_bridge.dart`：`download()` / `getInfo()` 加 optional `String? cookiesPath`
- `lib/core/models/download_task.dart`：加 `bool get needsCookies` getter
- `pubspec.yaml`：加 `file_picker: ^8.1.4`、dev `path_provider_platform_interface ^2.1.2`、`plugin_platform_interface ^2.1.8`

### Fixed
- N/A (此版為功能擴充)

### Verified on Device (Note 9 SM-N960F)
- ✅ logcat 確認 ADB intent extra `pma_cookies_path` → MainActivity → yt-dlp `--cookies <path>`
- ✅ `fvm flutter analyze` 0 issue
- ✅ `fvm flutter test test/` 全部測試通過
- ✅ `fvm flutter build apk --debug` 成功 (~263MB)
- ⏳ mobile-mcp UI flow 驗證（FilePicker 匯入 / needsCookies 按鈕 / library sort）見 `.omc/autopilot/full-feature-verification-checklist.md`
