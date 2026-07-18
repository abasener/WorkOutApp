import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database.dart';
import '../models/progress_photo.dart';

class ProgressPhotoRepository {
  final DatabaseHelper _db;
  ProgressPhotoRepository(this._db);

  Future<List<ProgressPhoto>> getAll() async {
    final rows = await (await _db.database)
        .query('progress_photos', orderBy: 'date ASC, taken_at ASC');
    return rows.map(ProgressPhoto.fromMap).toList();
  }

  Future<int> insert(ProgressPhoto photo) async =>
      (await _db.database).insert('progress_photos', photo.toMap());

  /// Deletes both the DB row and its backing file — an orphaned image file
  /// isn't visible anywhere in the app, but there's no reason to leave it
  /// taking up storage once its log entry is gone.
  Future<void> delete(ProgressPhoto photo) async {
    await (await _db.database)
        .delete('progress_photos', where: 'id = ?', whereArgs: [photo.id]);
    final file = File(photo.filePath);
    if (await file.exists()) await file.delete();
  }

  /// Copies a picked image into this app's own document storage (under
  /// `progress_photos/`) with a unique, collision-proof filename, and
  /// returns the new absolute path to store on the [ProgressPhoto] row.
  /// Image pickers commonly hand back a path in a cache/temp location that
  /// isn't guaranteed to persist, so the file needs its own permanent copy.
  Future<String> storePickedFile(String pickedPath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'progress_photos'));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final ext = p.extension(pickedPath);
    final destPath = p.join(
      photosDir.path,
      '${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await File(pickedPath).copy(destPath);
    return destPath;
  }

  /// Same idea as [storePickedFile], but for image bytes generated in code
  /// rather than picked from the camera/library — used only by
  /// `TestDataService`'s synthetic demo photos.
  Future<String> storeBytes(Uint8List bytes, {String ext = '.png'}) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'progress_photos'));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final destPath = p.join(
      photosDir.path,
      '${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  /// Deletes every logged photo and its backing file — used when reloading
  /// demo data, so re-running "Load test data" doesn't just keep piling up
  /// another batch of synthetic photos on top of the last one.
  Future<void> deleteAll() async {
    final all = await getAll();
    for (final photo in all) {
      await delete(photo);
    }
  }
}
