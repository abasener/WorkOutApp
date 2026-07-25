import '../database.dart';
import '../models/metric_entry.dart';

class MetricsRepository {
  final DatabaseHelper _db;
  MetricsRepository(this._db);

  Future<List<MetricEntry>> getByType(MetricType type, {int? limit}) async {
    // `date DESC` alone doesn't disambiguate multiple same-day entries (e.g.
    // logging soreness both morning and evening) — without a tiebreaker,
    // SQLite falls back to insertion order, so the *first* entry of the day
    // would win over a later same-day update. `time_slot DESC` puts an
    // explicit PM entry ahead of an AM one for the same date regardless of
    // which was actually *saved* more recently in real time (backfilling or
    // correcting an AM entry after PM was already logged shouldn't make the
    // AM one look "more recent" just because it was saved later) — legacy
    // rows with no slot (`NULL`) sort last in `DESC`, behind any explicitly
    // slotted entry for the same date. `logged_at DESC, id DESC` remains the
    // tiebreaker for same-slot or both-unslotted entries.
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ?',
      whereArgs: [type.key],
      orderBy: 'date DESC, time_slot DESC, logged_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(MetricEntry.fromMap).toList();
  }

  Future<MetricEntry?> getLatest(MetricType type) async {
    final rows = await getByType(type, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// All entries of [type] on a specific date, most recently logged first —
  /// used where multiple same-day entries are expected (e.g. soreness).
  Future<List<MetricEntry>> getByTypeAndDate(
    MetricType type,
    String date,
  ) async {
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ? AND date = ?',
      whereArgs: [type.key, date],
      orderBy: 'logged_at DESC',
    );
    return rows.map(MetricEntry.fromMap).toList();
  }

  /// The single entry (if any) logged for [type] on [date] in exactly
  /// [slot] — what `SorenessBodyMapForm` loads to show "what's currently
  /// logged here" when the user picks a date + AM/PM combination.
  Future<MetricEntry?> getByTypeDateAndSlot(
    MetricType type,
    String date,
    SorenessTimeSlot slot,
  ) async {
    final rows = await (await _db.database).query(
      'metrics_log',
      where: 'metric_type = ? AND date = ? AND time_slot = ?',
      whereArgs: [type.key, date, slot.key],
    );
    return rows.isEmpty ? null : MetricEntry.fromMap(rows.first);
  }

  /// Replaces whatever's logged for [e]'s exact `(metricType, date,
  /// timeSlot)` combination — the actual "override a wrong past log"
  /// mechanism: without this, saving the same date+slot again would just
  /// append a second row rather than correct the first. [e.timeSlot] must
  /// be set (soreness entries always have one going forward).
  Future<void> upsertSorenessEntry(MetricEntry e) async {
    assert(e.timeSlot != null, 'upsertSorenessEntry requires a timeSlot');
    final db = await _db.database;
    await db.delete(
      'metrics_log',
      where: 'metric_type = ? AND date = ? AND time_slot = ?',
      whereArgs: [e.metricType.key, e.date, e.timeSlot!.key],
    );
    await db.insert('metrics_log', e.toMap());
  }

  /// Every logged metric entry (all types) — used by the Metrics "Days" tab
  /// to build a day-grouped, editable view across steps/sleep/soreness.
  Future<List<MetricEntry>> getAll() async {
    final rows = await (await _db.database).query(
      'metrics_log',
      orderBy: 'date DESC',
    );
    return rows.map(MetricEntry.fromMap).toList();
  }

  Future<int> insert(MetricEntry e) async =>
      (await _db.database).insert('metrics_log', e.toMap());

  Future<void> update(MetricEntry e) async => (await _db.database).update(
    'metrics_log',
    e.toMap(),
    where: 'id = ?',
    whereArgs: [e.id],
  );

  Future<void> delete(int id) async => (await _db.database).delete(
    'metrics_log',
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Natural per-day decay rate for a soreness rating once nothing new gets
  /// logged for a region — see `effectiveSorenessLevel` below for the full
  /// reasoning. Deliberately a rough, flat starting point, not a precise
  /// formula: soreness is entirely self-reported on a 0-5 scale, and what a
  /// "5" *means* is inherently personal — one person's "5" is "pushed hard,
  /// expect to feel it for about a week"; another's is "quite sore, back to
  /// normal in a few days." A single flat rate can't capture that gap.
  /// **Earmarked as the natural next step**, deliberately not built yet:
  /// learn each user's own actual gap-then-relog pattern (how much a
  /// region's reported soreness tends to have dropped after N days without
  /// training it) rather than assuming everyone decays at the same rate —
  /// deferred because a new user has no history yet to learn a personal
  /// rate from, and it may end up varying by muscle group too, not just by
  /// person. Grounded loosely in DOMS research (soreness typically resolves
  /// over roughly 3-7 days post-exercise per general sports-medicine
  /// literature), not an exact number pulled from a study — there's no
  /// published "points per day" curve for a subjective 0-5 self-report
  /// scale.
  static const double sorenessDecayPerDay = 1 / 1.5; // ~1 level every 1.5 days

  static double decayedSorenessLevel(double loggedValue, int daysSinceLogged) {
    if (daysSinceLogged <= 0) return loggedValue;
    return (loggedValue - sorenessDecayPerDay * daysSinceLogged).clamp(
      0.0,
      5.0,
    );
  }

  /// The soreness level to actually treat as current for [region] — the
  /// most recently logged value, decayed for however many days have passed
  /// since it was logged (0 if nothing's ever been logged for it).
  ///
  /// Logging twice in a day (e.g. morning and evening) already works with no
  /// special AM/PM handling needed here: the most recent same-day entry
  /// naturally wins via `getLatest`'s `date DESC, logged_at DESC` ordering,
  /// and logging only once in a day means that single entry just carries
  /// through the rest of that day unchanged (`daysSinceLogged` stays 0 until
  /// the calendar date itself moves on) — both exactly the intended
  /// behavior, already true before this method existed. The actual gap this
  /// closes: previously, a log from arbitrarily far in the past (a week, a
  /// month) was treated as still 100% current forever, with nothing pulling
  /// it back down; now it fades toward 0 the longer it goes unconfirmed,
  /// matching how soreness actually resolves in real life when nothing new
  /// happens to a muscle.
  Future<double> effectiveSorenessLevel(
    SorenessRegion region, {
    DateTime? now,
  }) async {
    final latest = await getLatest(MetricTypeKey.forSorenessRegion(region));
    if (latest == null) return 0;
    final daysSince = (now ?? DateTime.now())
        .difference(DateTime.parse(latest.date))
        .inDays;
    return decayedSorenessLevel(latest.value, daysSince);
  }
}
