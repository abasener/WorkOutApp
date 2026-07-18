/// One progress-photo log entry — the file itself lives in app storage
/// (`ProgressPhotoRepository._photosDir`), this just records where and when.
/// Multiple entries can share a [date] (different angles/poses the same day).
class ProgressPhoto {
  final int? id;
  final String date;
  final String filePath;
  final String takenAt;

  const ProgressPhoto({
    this.id,
    required this.date,
    required this.filePath,
    required this.takenAt,
  });

  factory ProgressPhoto.fromMap(Map<String, dynamic> m) => ProgressPhoto(
        id: m['id'] as int?,
        date: m['date'] as String,
        filePath: m['file_path'] as String,
        takenAt: m['taken_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'file_path': filePath,
        'taken_at': takenAt,
      };
}
