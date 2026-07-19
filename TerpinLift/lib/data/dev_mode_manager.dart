import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Whether the demo/personal data-set switcher and its reset/sample-data
/// tools are visible at all. Off by default (and for any real end user) —
/// a plain marker file, same pattern as `ProfileManager`'s active-profile
/// flag, so it's readable before/independent of which profile's database is
/// open and can never be wiped by a demo reset. Unlocking it is the hidden
/// long-press-then-type-a-code gesture on Settings' Reset Data button (see
/// `06_SCREEN_settings.md`), not a normal UI toggle — the toggle that
/// appears once unlocked is just for conveniently turning it back off.
abstract class DevModeManager {
  static const _flagFileName = 'dev_mode.txt';

  static Future<File> _flagFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, _flagFileName));
  }

  static Future<bool> isEnabled() async {
    final file = await _flagFile();
    if (!await file.exists()) return false;
    return (await file.readAsString()).trim() == '1';
  }

  static Future<void> setEnabled(bool enabled) async {
    final file = await _flagFile();
    await file.writeAsString(enabled ? '1' : '0');
  }
}
