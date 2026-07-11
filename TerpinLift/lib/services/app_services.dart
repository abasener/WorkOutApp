import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/profile_manager.dart';
import '../data/repositories/bodyweight_repository.dart';
import '../data/repositories/cycle_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/lift_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/workout_plan_repository.dart';
import 'home_trend_settings.dart';
import 'test_data_service.dart';
import 'units.dart';
import 'user_profile.dart';

abstract final class AppServices {
  static late DatabaseHelper db;
  static late ExerciseRepository exercises;
  static late LiftRepository lifts;
  static late BodyweightRepository bodyweight;
  static late MetricsRepository metrics;
  static late CycleRepository cycle;
  static late SettingsRepository settings;
  static late WorkoutPlanRepository workoutPlans;

  /// Which data set is currently active — see `ProfileManager`. Exposed as a
  /// listenable so screens (Settings' toggle) can reflect the current state
  /// without threading it through every widget.
  static final activeProfile = ValueNotifier<AppProfile>(AppProfile.personal);

  static const _unitSettingKey = 'weight_unit';
  static const _genderSettingKey = 'gender';
  static const _birthYearSettingKey = 'birth_year';
  static const _hideWeightSettingKey = 'hide_weight';
  static const _homeTrendExerciseIdsKey = 'home_trend_exercise_ids';
  static const _homeTrendMonthsKey = 'home_trend_months';

  /// Bump whenever a write happens that other screens should reflect.
  static final reloadSignal = ValueNotifier<int>(0);
  static void signalReload() => reloadSignal.value++;

  static Future<void> init() async {
    await ProfileManager.migrateLegacyDbIfNeeded();
    final profile = await ProfileManager.loadActiveProfile();
    activeProfile.value = profile;
    _bindRepositories(DatabaseHelper(profile: profile));

    // Touch the database once at startup so onCreate/seeding runs eagerly
    // rather than lazily on first query.
    await db.database;
    await _loadPersistedSettings();
  }

  static void _bindRepositories(DatabaseHelper helper) {
    db = helper;
    exercises = ExerciseRepository(db);
    lifts = LiftRepository(db);
    bodyweight = BodyweightRepository(db);
    metrics = MetricsRepository(db);
    cycle = CycleRepository(db);
    settings = SettingsRepository(db);
    workoutPlans = WorkoutPlanRepository(db);
  }

  static Future<void> _loadPersistedSettings() async {
    final storedUnit = await settings.get(_unitSettingKey);
    Units.current = WeightUnitKey.fromKey(storedUnit);

    final storedGender = await settings.get(_genderSettingKey);
    UserProfile.gender = GenderKey.fromKey(storedGender);

    final storedBirthYear = await settings.get(_birthYearSettingKey);
    UserProfile.birthYear = storedBirthYear == null ? null : int.tryParse(storedBirthYear);

    final storedHideWeight = await settings.get(_hideWeightSettingKey);
    Units.hideWeight = storedHideWeight == 'true';

    final storedTrendIds = await settings.get(_homeTrendExerciseIdsKey);
    HomeTrendSettings.exerciseIds = storedTrendIds
        ?.split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();

    final storedTrendMonths = await settings.get(_homeTrendMonthsKey);
    HomeTrendSettings.months = int.tryParse(storedTrendMonths ?? '') ?? 6;
  }

  /// Swaps to the other profile's database file entirely — personal and
  /// demo data never share a file, so this can never overwrite or mix them.
  /// Entering `demo` always reseeds a clean synthetic set first (per the
  /// user's ask: toggling demo off and back on should give a fresh start,
  /// not whatever was left over from last time); entering `personal` never
  /// touches its data, it just reopens the existing file as-is.
  static Future<void> switchProfile(AppProfile profile) async {
    if (profile == activeProfile.value) return;
    await db.close();
    _bindRepositories(DatabaseHelper(profile: profile));
    await db.database;
    if (profile == AppProfile.demo) {
      await TestDataService.load();
    }
    await _loadPersistedSettings();
    await ProfileManager.saveActiveProfile(profile);
    activeProfile.value = profile;
    signalReload();
  }

  /// Regenerates the demo data set from scratch without leaving demo mode —
  /// "start over" if something got messed up while poking around.
  static Future<void> resetDemoData() async {
    if (activeProfile.value != AppProfile.demo) return;
    await TestDataService.load();
    await _loadPersistedSettings();
    signalReload();
  }

  static Future<void> setWeightUnit(WeightUnit unit) async {
    Units.current = unit;
    await settings.set(_unitSettingKey, unit.key);
    signalReload();
  }

  static Future<void> setGender(Gender gender) async {
    UserProfile.gender = gender;
    await settings.set(_genderSettingKey, gender.key);
    signalReload();
  }

  static Future<void> setBirthYear(int? birthYear) async {
    UserProfile.birthYear = birthYear;
    await settings.set(_birthYearSettingKey, birthYear?.toString() ?? '');
    signalReload();
  }

  static Future<void> setHideWeight(bool hide) async {
    Units.hideWeight = hide;
    await settings.set(_hideWeightSettingKey, hide.toString());
    signalReload();
  }

  static Future<void> setHomeTrendExerciseIds(List<int> ids) async {
    HomeTrendSettings.exerciseIds = ids;
    await settings.set(_homeTrendExerciseIdsKey, ids.join(','));
    signalReload();
  }

  static Future<void> setHomeTrendMonths(int months) async {
    HomeTrendSettings.months = months;
    await settings.set(_homeTrendMonthsKey, months.toString());
    signalReload();
  }
}
