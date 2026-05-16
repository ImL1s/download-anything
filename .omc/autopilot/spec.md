# Personal Media Archiver — Spec (Phase 0)

## 1. 產品定位
- **名稱**：Personal Media Archiver（PMA）
- **平台**：Android-only（Flutter）
- **定位**：個人媒體保存／整理器，不是通用下載器
- **三大邊界**：
  1. 不繞過 DRM/付費牆/驗證機制
  2. 不集中化憑證、不雲端同步、預設不蒐集資料
  3. 不做遠端熱更新功能碼（合 Apple 2.5.2/Google Device Abuse 規則）

## 2. 使用情境（MVP）
1. 貼上 URL → 政策分類器標示「允許/警告/拒絕」→ 開始下載
2. 下載任務管理（佇列、進度、暫停、重試、取消）
3. 本機媒體庫瀏覽 + 開啟外部播放器
4. 設定（儲存位置、政策強度、關於）

## 3. 系統架構
```
lib/
├── main.dart
├── app.dart                       # MaterialApp + theme + router
├── theme/
│   └── app_theme.dart             # Teal + Atkinson Hyperlegible
├── core/
│   ├── models/                    # DownloadTask, MediaItem, PolicyDecision
│   ├── policy/                    # SourcePolicy classifier
│   ├── download/                  # DownloadEngine (dio + Isolate)
│   ├── library/                   # MediaLibrary (JSON store via path_provider)
│   └── extractors/                # DirectUrlExtractor (others: future)
├── state/                         # Riverpod providers
└── ui/
    ├── pages/                     # home / queue / library / settings
    └── widgets/                   # UrlInputCard, TaskCard, MediaCard, PolicyBanner
```

## 4. 技術選型
| 用途 | Package | 原因 |
|---|---|---|
| 狀態管理 | `flutter_riverpod` | 官方推薦、便於測試 |
| HTTP 下載 | `dio` | 支援進度 callback、cancel token |
| 路由 | `go_router` | declarative + deep links |
| 檔案路徑 | `path_provider` | 系統相容 |
| Storage Access | `saf_util` / `permission_handler` | SAF + 最小權限 |
| 字體 | `google_fonts` | Atkinson Hyperlegible |
| 圖示 | `material_symbols_icons` | M3 Expressive |
| 持久化 | 純 JSON file | 避免 sqflite 平台 plugin 複雜度 |

## 5. 設計系統（來自 ui-ux-pro-max）
- **主色**：`#0D9488` (Teal 600)
- **副色**：`#14B8A6` (Teal 500)
- **CTA**：`#F97316` (Orange 500)
- **背景 Light**：`#F0FDFA`
- **背景 Dark**：`#0F1F1D`
- **文字 Light**：`#134E4A`
- **文字 Dark**：`#E2F4F0`
- **字體**：Atkinson Hyperlegible（無障礙、高可讀）
- **風格**：Material 3 Expressive + Micro-interactions
- **動效**：150-300ms 過渡、loading spinner、success/error 狀態動畫

## 6. 來源政策分類器
- **ALLOW**：純直連媒體 URL（.mp4/.m4a/.mp3/.wav/.webm/.ogg）、podcast RSS feed、**所有 yt-dlp 支援的公開社交平台**（YouTube、Twitter/X、Instagram、TikTok、Bilibili、Vimeo、Twitch、SoundCloud 等 1000+ 站）
- **WARN**：未知主機、HTML 頁面
- **BLOCK**：已知 DRM/付費牆網域（Netflix、Disney+、Spotify、Apple Music、HBO Max 等）

實作上分兩條路徑：
1. **直連 URL** → 純 Dart `dio` 下載
2. **社交平台** → 透過 platform channel 呼叫 youtubedl-android（yt-dlp + Python via Chaquopy）取得直連 stream URL 或直接下載

實作策略：
1. 解析 URL 取得 scheme、host、path、副檔名
2. 比對 BLOCK 名單（精確 host suffix match）
3. 比對 ALLOW 擴展名與 RSS Content-Type 探測
4. 其餘標記 WARN，要求使用者確認

## 7. 下載引擎
- 用 `dio` + `Range` header 支援續傳
- 進度透過 `onReceiveProgress` 回到 Riverpod state
- 佇列上限可設定（預設 2 個並行）
- `CancelToken` 處理取消
- 寫入位置：`getExternalStorageDirectory()` 下的 `PersonalMediaArchiver/` 子目錄
- 檔名衝突時加 `(1)`、`(2)` 後綴

## 8. 媒體庫
- JSON 檔案 `library.json` 儲存於 app 私有目錄
- 結構：`{ "items": [{ "id", "title", "filename", "filepath", "size", "mimeType", "sourceUrl", "savedAt" }] }`
- 顯示縮圖（影片用 `video_thumbnail`，第一版可省略，先顯示通用 icon）

## 9. 設定
- 儲存位置（顯示目前路徑，可改）
- 政策強度（strict / balanced / permissive）
- 並行下載數
- 關於頁面（版本、開源授權、政策聲明）

## 10. 驗證計畫
- 目標設備：Samsung Galaxy S25 Ultra（Android 16）`R5CX10VFFBA`
- 測試 URL：
  - **必過 (Direct URL)**：`https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4`
  - **必過 (Direct MP3)**：`https://download.samplelib.com/mp3/sample-3s.mp3`
  - **必過 (YouTube)**：CC0/CC-BY 公開影片，如 NASA 官方頻道短片
  - **必過 (TikTok)**：公開 TikTok 影片（無需登入）
  - **必過 (Twitter/X)**：公開推文影片
  - **必擋 (DRM)**：`https://www.netflix.com/title/12345`
- 驗證方式：
  1. APK 安裝、App 啟動成功
  2. 貼上 mp4 URL，看到 ALLOW 標記
  3. 開始下載，進度條前進
  4. 下載完成後，`adb shell ls` 確認檔案存在
  5. `adb pull` 後 `md5sum` 對照原始檔
  6. 貼上 Netflix URL，看到 BLOCK 訊息
  7. 貼上 YouTube URL，看到 WARN 訊息

## 11. 開源與授權
- License：Apache-2.0
- README 三段聲明：用途、使用者責任、本機資料
- 預設不收 telemetry、不收 crash report、不雲端同步

## 12. 不在 MVP 範圍
- iOS / 桌面平台
- yt-dlp 整合（需要 platform channel + youtubedl-android）
- HLS/DASH 自製 parser
- DRM 內容
- 雲端同步、帳號系統
- App Store / Google Play 發佈流程
