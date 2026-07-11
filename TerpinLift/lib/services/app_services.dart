import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repositories/bodyweight_repository.dart';
import '../data/repositories/cycle_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/lift_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'units.dart';
import 'user_profile.dart';

abstract final class AppServices {
  static late final DatabaseHelper db;
  static late final ExerciseRepository exercises;
  static late final LiftRepository lifts;
  static late final BodyweightRepository bodyweight;
  static late final MetricsRepository metrics;
  static late final CycleRepository cycle;
  static late final SettingsRepository settings;

  static const _unitSettingKey = 'weight_unit';
  static const _genderSettingKey = 'gender';
  static const _birthYearSettingKey = 'birth_year';

  /// Bump whenever a write happens that other screens should reflect.
  static final reloadSignal = ValueNotifier<int>(0);
  static void signalReload() => reloadSignal.value++;

  static Future<void> init() async {
    db = DatabaseHelper();
    exercises = ExerciseRepository(db);
    lifts = LiftRepository(db);
    bodyweight = BodyweightRepository(db);
    metrics = MetricsRepository(db);
    cycle = CycleRepository(db);
    settings = SettingsRepository(db);

    // Touch the database once at startup so onCreate/seeding runs eagerly
    // rather than lazily on first query.
    await db.database;

    final storedUnit = await settings.get(_unitSettingKey);
    Units.current = WeightUnitKey.fromKey(storedUnit);

    final storedGender = await settings.get(_genderSettingKey);
    UserProfile.gender = GenderKey.fromKey(storedGender);

    final storedBirthYear = await settings.get(_birthYearSettingKey);
    UserProfile.birthYear = storedBirthYear == null ? null : int.tryParse(storedBirthYear);
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
}
