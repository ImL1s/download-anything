# Changelog

All notable changes to PMA are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
