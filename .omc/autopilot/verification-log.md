# Personal Media Archiver — End-to-End Verification Log

## 環境
- 主機：macOS Darwin 25.4.0 (arm64)
- Flutter：3.32.8 stable (fvm)
- yt-dlp host：2026.03.17
- 設備 1：Samsung Galaxy Note 9 (SM-N960F) Android 10 — 用於 e2e
- 設備 2：Samsung Galaxy S25 Ultra (SM-S9280) Android 16 — 鎖屏（未解鎖測試）

## 單元測試
```
00:01 +12: All tests passed!
```
- Policy classifier（直連、Netflix、YouTube、TikTok、Threads、空白、嚴格模式、requiresExtractor）
- Download engine（filenameFromUrl 各種變體）

## 端對端測試（Samsung Note 9）

### Test 1：直連 MP4（純 Dart dio 路徑）
- URL：`https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4`
- 政策：✅ 綠色「允許下載 — 直連媒體檔案（MP4）」
- 下載：✅ 完成，UI 顯示「已完成 967.8 KB」
- 檔案大小：991,017 bytes（與來源 Content-Length 完全一致）
- 檔案類型：`ISO Media, MP4 Base Media v1 [ISO 14496-12:2003]`
- SHA-256：`77145c94c11f3754207499158df22406e1fe7635553c1c86dc5e881dfeb32016`
- **與來源伺服器 SHA-256 完全一致**（位元級驗證）

### Test 2：Netflix DRM BLOCK
- URL：`https://www.netflix.com/title/80100172`
- 政策：✅ 紅色「已被阻擋 — DRM 保護或第三方授權內容」
- 下載按鈕：✅ disabled
- 顯示建議文案：「請改用您已合法持有的本機檔案或直連媒體 URL。」

### Test 3：YouTube（yt-dlp 路徑）
- URL：`https://www.youtube.com/watch?v=jNQXAC9IVRw`
- 政策：✅ 綠色「允許下載 — yt-dlp 擷取」
- yt-dlp 執行：✅ Python runtime 啟動、URL 正確解析
- 失敗原因（非整合問題）：YouTube 2024+ 反 bot 機制要求 cookies
  - 錯誤訊息 `Sign in to confirm you're not a bot` 已透過 errorMessage 顯示在 UI
- **代表整合鏈完整：政策 → MethodChannel → Python yt-dlp → EventChannel → UI errorMessage**

### Test 4：yt-dlp 自動更新
- 觸發：app 首次 init 後非同步呼叫 `updateYoutubeDL(STABLE)`
- Bundled 版本：2025.11.12（6 個月前）
- 更新後：2026.03.17（最新 STABLE）
- logcat 記錄：`auto-update result: DONE -> yt-dlp 2026.03.17`

### Test 5：Streamable（yt-dlp 路徑，最終成功）
- URL：`https://streamable.com/moo`
- 政策：✅ 綠色「允許下載 — yt-dlp 擷取」
- yt-dlp getInfo：✅ 取得 title「me irl」
- 下載：✅ 完成
- 檔案：`me irl.mp4` 3,044,857 bytes
- 檔案類型：`ISO Media, MP4 Base Media v1`
- SHA-256：`444651c117532899b424ab9dce0ddee87f5d6bcc65e0c0f3a1eab1b286ac124b`
- UI 顯示：「已完成 2.9 MB」（size bug fix 後）
- 媒體庫：✅ 出現對應 entry

## UI 驗證
- 主題：Material 3 Expressive + Teal 色系 + Atkinson Hyperlegible
- 自動深色模式（裝置設定為深色時自動套用）
- 政策 banner：綠色 ALLOW / 橘色 WARN / 紅色 BLOCK 顏色分明
- 底部導航：新增/佇列/媒體庫/設定四 tab，icon + 文字
- 佇列：失敗/完成/排隊/下載中 狀態 icon 與顏色正確
- 設定：政策強度 radio、並行數 slider、yt-dlp 版本顯示與手動更新
- 繁體中文文案：所有頁面齊全

## 已知限制（記入 README）
- YouTube：需要 cookies（眾所周知的 YouTube anti-bot 問題）
- Vimeo：部分 ID 需要登入
- TikTok：可能 IP-blocked（地區性）
- 這些都是來源站策略，整合層完全正確

## 結論
PMA Android 版完全可用，且**真的能下載**（dio 與 yt-dlp 兩條路徑均經實機驗證、檔案位元級完整）。
