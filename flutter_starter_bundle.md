# Flutter App Starter Bundle

Reference for a new Flutter Android app. Drop this into a new project chat so the assistant starts with context already loaded.

---

## Run on Device

```bash
cd ~/Documents/GitHub/[APP_NAME]/[APP_NAME] && flutter run -d [DEVICE_ID]
```

Run `flutter devices` if the device ID is unknown or has changed.

| Key | Action |
|-----|--------|
| `r` | Hot reload — keeps widget state, recompiles Dart |
| `R` | Hot restart — full restart, re-runs `main()`, re-opens DB |
| `q` | Quit |

**Hot restart is required** after any change to DB schema, seed data, or `AppServices.init()` — hot reload will not re-run those.

---

## Project Layout

```
lib/
  data/
    models/         # Plain Dart classes: fromMap, toMap, copyWith
    repositories/   # One file per model, only talks to DatabaseHelper
    database.dart   # DatabaseHelper: _onCreate, _onUpgrade, _migrate, seed
  services/
    app_services.dart   # Static singleton wiring repos together
    coin_service.dart   # Example domain service
    notification_service.dart
  screens/
    home/
    [feature]/      # One folder per major screen group
  widgets/          # Shared, stateless or lightly stateful
  theme/
    app_theme.dart  # All tokens: AppColors, AppText, AppSpacing, AppRadius
    app_icons.dart
  main.dart
```

`pubspec.yaml` lives one level up from `lib/`, inside the Flutter project folder.

---

## Database

### Stack

- **`sqflite`** — SQLite on-device, no ORM
- **`path_provider`** — resolves DB file path

### DatabaseHelper skeleton

```dart
class DatabaseHelper {
  static const _kDbVersion = 1; // increment with every schema change

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'app.db');
    return openDatabase(path, version: _kDbVersion,
        onCreate: _onCreate, onUpgrade: _onUpgrade,
        onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'));
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE things (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT    NOT NULL,
        created   TEXT    NOT NULL
      )
    ''');
    await _seedDefaults(db);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    for (var v = oldV + 1; v <= newV; v++) {
      await _migrate(db, v);
    }
  }

  Future<void> _migrate(Database db, int toVersion) async {
    switch (toVersion) {
      case 2:
        await db.execute('ALTER TABLE things ADD COLUMN color TEXT');
    }
  }
}
```

**Rules:**
- Always `PRAGMA foreign_keys = ON` in `onOpen`, not just `onCreate`.
- Every new column goes in `_migrate` AND in `_onCreate` (new installs skip upgrade).
- Never drop `_kDbVersion` below the shipped value — users will crash on downgrade.
- When doing multi-row UPDATEs that could violate a UNIQUE constraint during the loop, do a two-step: shift to a safe temporary value first, then shift to the target.

### Model pattern

```dart
class Thing {
  final int?   id;
  final String name;
  final String created; // ISO-8601 date string 'YYYY-MM-DD'

  const Thing({this.id, required this.name, required this.created});

  factory Thing.fromMap(Map<String, dynamic> m) => Thing(
    id:      m['id'] as int?,
    name:    m['name'] as String,
    created: m['created'] as String,
  );

  Map<String, dynamic> toMap() => {'name': name, 'created': created};

  Thing copyWith({String? name, String? created}) => Thing(
    id:      id,
    name:    name    ?? this.name,
    created: created ?? this.created,
  );
}
```

### Repository pattern

```dart
class ThingRepository {
  final DatabaseHelper _db;
  ThingRepository(this._db);

  Future<List<Thing>> getAll() async {
    final rows = await (await _db.database)
        .query('things', orderBy: 'created DESC');
    return rows.map(Thing.fromMap).toList();
  }

  Future<int> insert(Thing t) async =>
      (await _db.database).insert('things', t.toMap());

  Future<void> update(Thing t) async =>
      (await _db.database).update('things', t.toMap(),
          where: 'id = ?', whereArgs: [t.id]);

  Future<void> delete(int id) async =>
      (await _db.database).delete('things', where: 'id = ?', whereArgs: [id]);
}
```

---

## AppServices Singleton

Single initialization point wired in `main()` before `runApp`.

```dart
abstract final class AppServices {
  static late final DatabaseHelper  db;
  static late final ThingRepository things;

  static final reloadSignal = ValueNotifier<int>(0);
  static void  signalReload() => reloadSignal.value++;

  static final isDarkMode = ValueNotifier<bool>(false);

  static Future<void> init() async {
    db     = DatabaseHelper();
    things = ThingRepository(db);
    // load any persisted settings, fire reloadSignal after heavy work
  }
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppServices.init();
  runApp(const MyApp());
}
```

**Cross-screen refresh:** call `AppServices.signalReload()` after any write that other screens should reflect. Screens subscribe:

```dart
@override
void initState() {
  super.initState();
  AppServices.reloadSignal.addListener(_onReload);
  _load();
}
@override
void dispose() {
  AppServices.reloadSignal.removeListener(_onReload);
  super.dispose();
}
void _onReload() => _load();
```

---

## Theme: Design Tokens

All values live in `app_theme.dart`. **Never hardcode a color, size, or text style inline.**

```dart
// Colors
abstract class AppColors {
  static Color background    = const Color(0xFFFFFFFF);
  static Color surface       = const Color(0xFFF5F5F5);
  static Color border        = const Color(0xFFE0E0E0);
  static Color textPrimary   = const Color(0xFF111111);
  static Color textSecondary = const Color(0xFF888888);
  // define an accent or brand color per project
}

// Spacing — use these everywhere, never magic numbers
abstract class AppSpacing {
  static const double micro    =  4;
  static const double small    =  8;
  static const double standard = 12;
  static const double cardPad  = 16;
  static const double edge     = 20;
  static const double large    = 24;
  static const double xLarge   = 32;
  static const double cardGap  = 12; // vertical gap between cards
}

// Border radii
abstract class AppRadius {
  static const double pill   = 100;
  static const double button =  12;
  static const double card   =  16;
}

// Text styles — always .copyWith() to adjust a single property
abstract class AppText {
  static const pageHeader = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const subHeader  = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const bodyText   = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);
  static const smallText  = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
}
```

---

## Buttons

**Minimum tap target: 52 px tall.** Always full-width for primary actions.

```dart
// Primary
SizedBox(
  width: double.infinity,
  height: 52,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button)),
    ),
    onPressed: _saving ? null : _submit, // null = Flutter auto-disables
    child: _saving
        ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Text('Save'),
  ),
)

// Secondary / outlined
OutlinedButton(
  style: OutlinedButton.styleFrom(
    side: BorderSide(color: accentColor),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button)),
  ),
  onPressed: _cancel,
  child: const Text('Cancel'),
)
```

---

## Screen Templates

### Standard scrollable screen

```dart
Scaffold(
  backgroundColor: AppColors.background,
  body: CustomScrollView(
    slivers: [
      SliverAppBar(
        expandedHeight: 180,
        pinned: true,
        backgroundColor: accentColor,
        // flexibleSpace: FlexibleSpaceBar(...) for collapsing header
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Card(child: ...),
              const SizedBox(height: AppSpacing.cardGap),
              _Card(child: ...),
              const SizedBox(height: AppSpacing.xLarge), // bottom breathing room
            ],
          ),
        ),
      ),
    ],
  ),
)
```

### Card widget (local, not a global widget)

```dart
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.cardPad),
    decoration: BoxDecoration(
      color:        AppColors.surface,
      border:       Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: child,
  );
}
```

### Bottom sheet (custom styled)

```dart
await showModalBottomSheet(
  context: context,
  isScrollControlled: true,   // allows sheet to grow with keyboard
  backgroundColor: Colors.transparent,
  builder: (_) => Padding(
    padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.card)),
      ),
      padding: EdgeInsets.fromLTRB(
          AppSpacing.edge, AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
    ),
  ),
);
```

### Full-screen dialog (review / detail overlay)

```dart
Navigator.push(context, MaterialPageRoute(
  fullscreenDialog: true,
  builder: (_) => const SomeScreen(),
));
```

### Intercept system back button

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) Navigator.pop(context, 'dismissed');
  },
  child: Scaffold(...),
)
```

---

## Async / State Rules

```dart
// Always guard after every await
final result = await someRepo.getAll();
if (!mounted) return;
setState(() => _items = result);

// Loading pattern
bool _loading = true;

Future<void> _load() async {
  final items = await AppServices.things.getAll();
  if (!mounted) return;
  setState(() { _items = items; _loading = false; });
}

// Saving pattern — disables button during async work
bool _saving = false;

Future<void> _submit() async {
  setState(() => _saving = true);
  try {
    await AppServices.things.insert(newThing);
    if (mounted) Navigator.pop(context, true);
  } catch (_) {
    if (mounted) setState(() => _saving = false);
  }
}
```

---

## Charts and Progress Visualizations

All charts use `CustomPainter` — no third-party chart packages. This keeps the APK small and gives full pixel control.

### Progress bar

```dart
class ProgressBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final Color  color;
  const ProgressBar({required this.progress, required this.color, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: CustomPaint(
      size: Size.infinite,
      painter: _Painter(progress: progress.clamp(0.0, 1.0), color: color),
    ),
  );
}

class _Painter extends CustomPainter {
  final double progress;
  final Color  color;
  const _Painter({required this.progress, required this.color});

  static const _h   = 10.0;
  static const _top =  7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = const Radius.circular(_h / 2);
    // Track
    canvas.drawRRect(
      RRect.fromLTRBR(0, _top, size.width, _top + _h, rr),
      Paint()..color = AppColors.border,
    );
    // Fill
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, _top, size.width * progress, _top + _h, rr),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.progress != progress || old.color != color;
}
```

### Line chart

Draw a `Path` through data points, optionally fill below with a low-opacity area:

```dart
@override
void paint(Canvas canvas, Size size) {
  if (points.isEmpty) return;

  final minV = points.reduce(math.min);
  final maxV = points.reduce(math.max);
  final range = (maxV - minV).abs().clamp(1.0, double.infinity);

  double xOf(int i) => i / (points.length - 1) * size.width;
  double yOf(double v) => size.height - ((v - minV) / range * size.height * 0.8 + size.height * 0.1);

  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final x = xOf(i);
    final y = yOf(points[i]);
    if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
  }

  // Optional fill
  final fill = Path.from(path)
    ..lineTo(xOf(points.length - 1), size.height)
    ..lineTo(0, size.height)
    ..close();
  canvas.drawPath(fill, Paint()
    ..color = color.withValues(alpha: 0.12)
    ..style = PaintingStyle.fill);

  canvas.drawPath(path, Paint()
    ..color = color
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round);
}
```

### Bar chart

Equal-width bars with optional horizontal goal line:

```dart
@override
void paint(Canvas canvas, Size size) {
  if (bars.isEmpty) return;

  final maxV    = bars.reduce(math.max).clamp(1.0, double.infinity);
  final barW    = size.width / bars.length;
  final gap     = barW * 0.25;

  for (var i = 0; i < bars.length; i++) {
    final x  = i * barW + gap / 2;
    final h  = (bars[i] / maxV) * size.height * 0.85;
    final rect = Rect.fromLTWH(x, size.height - h, barW - gap, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = color,
    );
  }

  // Goal line
  if (goalValue != null) {
    final gy = size.height - (goalValue! / maxV) * size.height * 0.85;
    canvas.drawLine(Offset(0, gy), Offset(size.width, gy),
        Paint()..color = Colors.red..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
  }
}
```

### Pie / donut chart

```dart
@override
void paint(Canvas canvas, Size size) {
  final center = size.center(Offset.zero);
  final radius = size.shortestSide / 2 * 0.9;
  final inner  = radius * 0.55; // 0 for pie, >0 for donut

  double startAngle = -math.pi / 2;
  final total = slices.fold(0.0, (s, e) => s + e.value);

  for (final slice in slices) {
    final sweep = (slice.value / total) * 2 * math.pi;
    final paint = Paint()
      ..color     = slice.color
      ..style     = PaintingStyle.fill;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweep, true, paint);
    startAngle += sweep;
  }

  // Donut hole
  if (inner > 0) {
    canvas.drawCircle(center, inner,
        Paint()..color = AppColors.surface);
  }
}
```

### Usage wrapper (consistent across all chart types)

```dart
SizedBox(
  height: 180,
  child: LayoutBuilder(
    builder: (_, constraints) => CustomPaint(
      size: Size(constraints.maxWidth, 180),
      painter: MyChartPainter(data: _data, color: accentColor),
    ),
  ),
)
```

Use `LayoutBuilder` when the painter needs the actual rendered width (most bar and line charts do).

---

## Dates

All dates stored as `'YYYY-MM-DD'` strings in SQLite.

```dart
// Today as string
final today = DateTime.now().toIso8601String().substring(0, 10);

// Parse back
final d = DateTime.parse(someString);

// Compare dates only (strip time to avoid DST edge cases)
final aDate = DateTime(a.year, a.month, a.day);
final bDate = DateTime(b.year, b.month, b.day);
final diff  = aDate.difference(bDate).inDays;
```

---

## Build for Release

```bash
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```

Version in `pubspec.yaml`:  `version: 1.0.0+1`  → `major.minor.patch+buildCode`  
Only increment for Play Store uploads; local `flutter run` does not require it.

---

## Quick Checklist Before First Run on a New Device

1. Enable **Developer Options** on the phone.
2. Enable **USB Debugging**.
3. Run `flutter devices` — confirm the Pixel appears.
4. `flutter run -d [DEVICE_ID]` from inside the Flutter project folder (the one with `pubspec.yaml`).
5. First build takes 2–4 minutes; hot reload after that is nearly instant.
