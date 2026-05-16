## Handoff: team-plan → team-exec

- **Decided**: 實作 ccg 共識方案 **A（手動匯入 cookies.txt）+ F（best-effort 保留 player_client fallback + 文案說明）**。4 worker 並行：
  - W1 → cookies_service（核心 storage + 驗證）
  - W2 → 設定頁 UI（file picker + meta 顯示）
  - W3 → native + Dart bridge wiring（含 needsCookies error 偵測）
  - W4 → README 文案 + 真機 e2e 驗證

- **Rejected**:
  - B 自動抓 anon cookies — Codex sharp 觀察：「Mac 上無 cookies 本來就能下，anon cookies 證明不了任何事」
  - C WebView in-app browser — Google 越來越擋 in-app login，違反 PMA「無強制登入」精神
  - D bgutil-ytdlp-pot-provider — 要 Node.js sidecar 行動端不可行
  - E curl_cffi --impersonate — wheel 是 cp313+arm64，youtubedl-android Python 3.12 不 drop-in，要 fork AAR 超出 sprint

- **Risks**:
  - 真實 YouTube unlock 需要 user export 含 SID 的瀏覽器 cookies（隱私敏感不能用我的）
  - 本 sprint e2e 用 fake cookies (Netscape header + 假 youtube domain entries) 證明 wiring；最終 unlock 由 user 提供 real cookies 二次驗證
  - cookies 過期 ~6 個月，需 UI 提示

- **Files (current state)**:
  - `.omc/artifacts/ask/codex-*.md`, `.omc/artifacts/ask/gemini-*.md` (ccg 共識證據)
  - `MainActivity.kt` 已加 `applySiteSpecificArgs` (player_client fallback) + `maybeRunAdbTestUrl` (ADB e2e hook)
  - `lib/core/policy/source_policy.dart` 已含 youtube.com / youtu.be domain

- **Worker boundary（衝突避免）**:
  - W1: 新檔 `lib/core/cookies/cookies_service.dart` + `lib/state/providers.dart` 加 1 行 provider
  - W2: `lib/ui/pages/settings_page.dart` + `pubspec.yaml` 加 file_picker dep
  - W3: `android/app/src/main/kotlin/.../MainActivity.kt` + `lib/core/extractors/ytdlp_bridge.dart` + `lib/state/task_controller.dart` + `lib/core/models/download_task.dart`
  - W4: `README.md` + 新檔 `test/cookies_service_test.dart` + 新檔 `.omc/autopilot/yt-cookies-verification.md`

- **Remaining**: cookies_service 實作、設定頁 UI、bridge wiring、Note 9 真機 e2e（rebuild APK → push fake cookies → adb am start --es pma_test_url → 觀察 logcat 確認 `--cookies` flag 確實傳給 yt-dlp）
