import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Which data set is currently active. `personal` is real logged history;
/// `demo` is disposable synthetic data for trying features out. Each keeps
/// its own SQLite file (`terpinlift_personal.db` / `terpinlift_demo.db`) so
/// switching between them can never overwrite or mix the other's rows.
enum AppProfile { personal, demo }

/// Resolves per-profile database file paths and persists which profile is
/// active, independent of either database file — a plain marker file, not a
/// row inside one of the swappable databases, so the active profile survives
/// switching between them and isn't itself at risk of being wiped by a demo
/// reset.
abstract class ProfileManager {
  static const _personalDbName = 'terpinlift_personal.db';
  static const _demoDbName = 'terpinlift_demo.db';
  static const _legacyDbName = 'terpinlift.db';
  static const _flagFileName = 'active_profile.txt';

  static String _dbName(AppProfile profile) =>
      profile == AppProfile.personal ? _personalDbName : _demoDbName;

  static Future<String> dbPath(AppProfile profile) async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, _dbName(profile));
  }

  /// One-time migration for installs that predate the personal/demo split:
  /// if the old single `terpinlift.db` exists and the new personal file
  /// doesn't, rename it in place so whatever was already logged becomes the
  /// starting "personal" data set rather than silently vanishing.
  static Future<void> migrateLegacyDbIfNeeded() async {
    final dir = await getApplicationDocumentsDirectory();
    final legacy = File(join(dir.path, _legacyDbName));
    final personalPath = join(dir.path, _personalDbName);
    if (await legacy.exists() && !await File(personalPath).exists()) {
      await legacy.rename(personalPath);
    }
  }

  static Future<File> _flagFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, _flagFileName));
  }

  /// Defaults to `personal` — a fresh install, or one upgrading from before
  /// this feature existed, should never silently land in demo mode.
  static Future<AppProfile> loadActiveProfile() async {
    final file = await _flagFile();
    if (!await file.exists()) return AppProfile.personal;
    final contents = (await file.readAsString()).trim();
    return contents == 'demo' ? AppProfile.demo : AppProfile.personal;
  }

  static Future<void> saveActiveProfile(AppProfile profile) async {
    final file = await _flagFile();
    await file.writeAsString(profile == AppProfile.demo ? 'demo' : 'personal');
  }
}
