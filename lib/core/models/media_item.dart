class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.filename,
    required this.filepath,
    required this.sourceUrl,
    required this.sizeBytes,
    required this.savedAt,
    this.mimeType,
  });

  final String id;
  final String title;
  final String filename;
  final String filepath;
  final String sourceUrl;
  final int sizeBytes;
  final DateTime savedAt;
  final String? mimeType;

  bool get isAudio =>
      (mimeType ?? '').startsWith('audio/') ||
      _matchExt(['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus']);

  bool get isVideo =>
      (mimeType ?? '').startsWith('video/') ||
      _matchExt(['.mp4', '.m4v', '.mov', '.webm', '.mkv', '.avi']);

  bool _matchExt(List<String> exts) {
    final lower = filename.toLowerCase();
    for (final e in exts) {
      if (lower.endsWith(e)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filename': filename,
        'filepath': filepath,
        'sourceUrl': sourceUrl,
        'sizeBytes': sizeBytes,
        'savedAt': savedAt.toIso8601String(),
        'mimeType': mimeType,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        title: j['title'] as String,
        filename: j['filename'] as String,
        filepath: j['filepath'] as String,
        sourceUrl: j['sourceUrl'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        savedAt: DateTime.parse(j['savedAt'] as String),
        mimeType: j['mimeType'] as String?,
      );
}
