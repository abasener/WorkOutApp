import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/dev_mode_manager.dart';
import '../data/models/bodyweight_entry.dart';
import '../data/profile_manager.dart';
import '../data/repositories/bodyweight_repository.dart';
import '../data/repositories/cardio_repository.dart';
import '../data/repositories/custom_goal_repository.dart';
import '../data/repositories/custom_metric_repository.dart';
import '../data/repositories/cycle_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/hiit_repository.dart';
import '../data/repositories/hiit_routine_repository.dart';
import '../data/repositories/lift_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/repositories/progress_photo_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/todo_repository.dart';
import '../data/repositories/workout_plan_repository.dart';
import 'home_layout_settings.dart';
import 'home_trend_settings.dart';
import 'metric_layout_settings.dart';
import 'test_data_service.dart';
import 'units.dart';
import 'user_profile.dart';

abstract final class AppServices {
  static late DatabaseHelper db;
  static late ExerciseRepository exercises;
  static late LiftRepository lifts;
  static late CardioRepository cardio;
  static late HiitRepository hiit;
  static late HiitRoutineRepository hiitRoutines;
  static late BodyweightRepository bodyweight;
  static late MetricsRepository metrics;
  static late CycleRepository cycle;
  static late SettingsRepository settings;
  static late WorkoutPlanRepository workoutPlans;
  static late CustomGoalRepository customGoals;
  static late CustomMetricRepository customMetrics;
  static late ProgressPhotoRepository progressPhotos;
  static late TodoRepository todos;

  /// Which data set is currently active — see `ProfileManager`. Exposed as a
  /// listenable so screens (Settings' toggle) can reflect the current state
  /// without threading it through every widget.
  static final activeProfile = ValueNotifier<AppProfile>(AppProfile.personal);

  /// Gates the demo/personal switcher and its reset/sample-data tools in
  /// Settings — see `DevModeManager`. Off (and the data-set UI hidden, and
  /// the active profile forced to personal) for any normal use; unlocked via
  /// a long-press-then-type-a-code gesture, not a visible toggle, until
  /// after it's on.
  static final devModeEnabled = ValueNotifier<bool>(false);

  /// Which saved `WorkoutTemplate` Day Select/Home's planner card currently
  /// show (designFiles/10_WORKOUT_PLANNER.md "Multi-template switching") —
  /// `null` means "no explicit choice made yet," which falls back to
  /// `workoutPlans.getDefaultTemplate()`, matching the app's behavior before
  /// switching existed. The Workouts tab (past logged history) deliberately
  /// never reads this — `WorkoutPlanRepository.getAllDaysById()` resolves a
  /// session's day regardless of which template is currently active.
  static int? activeTemplateId;

  static const _unitSettingKey = 'weight_unit';
  static const _genderSettingKey = 'gender';
  static const _birthYearSettingKey = 'birth_year';
  static const _hideWeightSettingKey = 'hide_weight';
  static const _stepsGoalSettingKey = 'steps_goal';
  static const _weightGoalSettingKey = 'weight_goal_lb';
  static const _sleepGoalSettingKey = 'sleep_goal_hours';
  static const _homeTrendMonthsKey = 'home_trend_months';
  static const _homeWidgetOrderKey = 'home_widget_order';
  static const _metricWidgetOrderKey = 'metric_widget_order';
  static const _activeTemplateIdKey = 'active_template_id';
  static const _onboardingCompleteKey = 'onboarding_complete';

  /// Bump whenever a write happens that other screens should reflect.
  static final reloadSignal = ValueNotifier<int>(0);
  static void signalReload() => reloadSignal.value++;

  static Future<void> init() async {
    await ProfileManager.migrateLegacyDbIfNeeded();
    devModeEnabled.value = await DevModeManager.isEnabled();
    var profile = await ProfileManager.loadActiveProfile();
    // If dev mode got turned off (or was never on) while the demo profile
    // happened to be active — e.g. a previous session left it there — land
    // back on personal instead of silently opening a data set the user can
    // no longer reach any controls for.
    if (!devModeEnabled.value && profile == AppProfile.demo) {
      profile = AppProfile.personal;
      await ProfileManager.saveActiveProfile(profile);
    }
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
    cardio = CardioRepository(db);
    hiit = HiitRepository(db);
    hiitRoutines = HiitRoutineRepository(db);
    bodyweight = BodyweightRepository(db);
    metrics = MetricsRepository(db);
    cycle = CycleRepository(db);
    settings = SettingsRepository(db);
    workoutPlans = WorkoutPlanRepository(db);
    customGoals = CustomGoalRepository(db);
    customMetrics = CustomMetricRepository(db);
    progressPhotos = ProgressPhotoRepository(db);
    todos = TodoRepository(db);
  }

  static Future<void> _loadPersistedSettings() async {
    final storedUnit = await settings.get(_unitSettingKey);
    Units.current = WeightUnitKey.fromKey(storedUnit);

    final storedGender = await settings.get(_genderSettingKey);
    UserProfile.gender = GenderKey.fromKey(storedGender);

    final storedBirthYear = await settings.get(_birthYearSettingKey);
    UserProfile.birthYear = storedBirthYear == null
        ? null
        : int.tryParse(storedBirthYear);

    final storedHideWeight = await settings.get(_hideWeightSettingKey);
    Units.hideWeight = storedHideWeight == 'true';

    final storedStepsGoal = await settings.get(_stepsGoalSettingKey);
    UserProfile.stepsGoal = int.tryParse(storedStepsGoal ?? '') ?? 10000;

    // No fallback default for these two -- unlike stepsGoal, "no goal set"
    // is the common, legitimate starting state.
    final storedWeightGoal = await settings.get(_weightGoalSettingKey);
    UserProfile.weightGoalLb = storedWeightGoal == null
        ? null
        : double.tryParse(storedWeightGoal);

    final storedSleepGoal = await settings.get(_sleepGoalSettingKey);
    UserProfile.sleepGoalHours = storedSleepGoal == null
        ? null
        : double.tryParse(storedSleepGoal);

    final storedTrendMonths = await settings.get(_homeTrendMonthsKey);
    HomeTrendSettings.months = int.tryParse(storedTrendMonths ?? '') ?? 6;

    final storedWidgetOrder = await settings.get(_homeWidgetOrderKey);
    HomeLayoutSettings.order = storedWidgetOrder
        ?.split(',')
        .where((s) => s.isNotEmpty)
        .map(HomeLayoutItem.fromToken)
        .whereType<HomeLayoutItem>()
        .toList();

    final storedMetricOrder = await settings.get(_metricWidgetOrderKey);
    MetricLayoutSettings.order = storedMetricOrder
        ?.split(',')
        .where((s) => s.isNotEmpty)
        .map(MetricLayoutItem.fromToken)
        .whereType<MetricLayoutItem>()
        .toList();

    final storedActiveTemplateId = await settings.get(_activeTemplateIdKey);
    activeTemplateId = storedActiveTemplateId == null
        ? null
        : int.tryParse(storedActiveTemplateId);

    await _resolveOnboardingFlag();
  }

  /// Decides whether this profile should show the onboarding survey.
  /// A profile that already has the flag written just uses it. One that
  /// doesn't (every profile from before this feature existed) is
  /// grandfathered in as already-onboarded if it shows any sign of prior
  /// use (any setting, any logged data) — onboarding only ever shows for a
  /// genuinely blank profile, never retroactively for one already in use.
  static Future<void> _resolveOnboardingFlag() async {
    final stored = await settings.get(_onboardingCompleteKey);
    if (stored != null) {
      UserProfile.onboardingComplete = stored == 'true';
      return;
    }
    final hasPriorActivity = await db.hasAnyPriorActivity();
    UserProfile.onboardingComplete = hasPriorActivity;
    if (hasPriorActivity) {
      await settings.set(_onboardingCompleteKey, 'true');
    }
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

  /// Takes the demo profile back through onboarding — "start over" if
  /// something got messed up while poking around, and doubles as the way to
  /// preview/test the onboarding survey without touching real personal data
  /// (which lives in an entirely separate database file and is never
  /// touched by this). Clears every stored setting for the demo profile
  /// (`SettingsRepository.clearAll`), wipes its logged data (lift/cardio/
  /// HIIT/bodyweight/metrics/cycle — `wipeEverythingAndReseed`, exercises
  /// reseeded but no synthetic history generated), and flips
  /// `onboardingComplete` back to false so `AppRoot` shows `OnboardingFlow`
  /// next. Deliberately does **not** regenerate synthetic history —
  /// `completeOnboarding` leaves the demo profile genuinely empty afterward
  /// too, same as a real fresh install, so this doubles as "what does a new
  /// user actually see." `loadSampleDemoData` is the separate, explicit way
  /// to fill it back in with made-up history once you're looking at the
  /// empty app.
  static Future<void> resetDemoDataToOnboarding() async {
    if (activeProfile.value != AppProfile.demo) return;
    await settings.clearAll();
    await db.wipeEverythingAndReseed();
    UserProfile.gender = Gender.female;
    UserProfile.birthYear = null;
    UserProfile.stepsGoal = 10000;
    UserProfile.onboardingComplete = false;
    Units.current = WeightUnit.lb;
    Units.hideWeight = false;
    HomeTrendSettings.months = 6;
    HomeLayoutSettings.order = null;
    MetricLayoutSettings.order = null;
    signalReload();
  }

  /// Finishes the onboarding survey: applies what the user entered
  /// (gender/birth year/starting weight) plus the fixed post-onboarding
  /// defaults (7,000 step goal, lb, weight shown not hidden). Never
  /// generates synthetic history, on either profile — a brand new personal
  /// install should start genuinely empty except for what the user
  /// themselves just entered, and (per the user's call) so should the demo
  /// profile right after "Reset demo data," so it actually shows what a new
  /// user sees rather than being immediately re-filled with made-up data.
  /// See `loadSampleDemoData` for the separate, explicit way to fill the
  /// demo profile back in afterward.
  static Future<void> completeOnboarding({
    required Gender gender,
    int? birthYear,
    double? startingWeightLb,
  }) async {
    await setGender(gender);
    await setBirthYear(birthYear);
    await setStepsGoal(7000);
    await setWeightUnit(WeightUnit.lb);
    await setHideWeight(false);

    if (startingWeightLb != null) {
      await bodyweight.insert(
        BodyweightEntry(
          date: DateTime.now().toIso8601String().substring(0, 10),
          weight: startingWeightLb,
        ),
      );
    }

    UserProfile.onboardingComplete = true;
    await settings.set(_onboardingCompleteKey, 'true');
    signalReload();
  }

  /// Explicitly fills the demo profile with ~2 months of made-up history —
  /// separate from `resetDemoDataToOnboarding`/`completeOnboarding` above,
  /// which now leave it empty on purpose. This is the "I can load in the
  /// demo data if I want" step: no settings touched, no onboarding, just
  /// `TestDataService.load()` against whichever profile is active (no-op
  /// unless that's demo).
  static Future<void> loadSampleDemoData() async {
    if (activeProfile.value != AppProfile.demo) return;
    await TestDataService.load();
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

  static Future<void> setStepsGoal(int goal) async {
    UserProfile.stepsGoal = goal;
    await settings.set(_stepsGoalSettingKey, goal.toString());
    signalReload();
  }

  /// `null` clears the goal (deletes the stored key) rather than writing a
  /// placeholder value — clearing the Settings field is a legitimate way to
  /// go back to "no goal set", not an error state like an empty Steps goal
  /// would be.
  static Future<void> setWeightGoal(double? goalLb) async {
    UserProfile.weightGoalLb = goalLb;
    if (goalLb == null) {
      await settings.delete(_weightGoalSettingKey);
    } else {
      await settings.set(_weightGoalSettingKey, goalLb.toString());
    }
    signalReload();
  }

  static Future<void> setSleepGoal(double? goalHours) async {
    UserProfile.sleepGoalHours = goalHours;
    if (goalHours == null) {
      await settings.delete(_sleepGoalSettingKey);
    } else {
      await settings.set(_sleepGoalSettingKey, goalHours.toString());
    }
    signalReload();
  }

  static Future<void> setHomeTrendMonths(int months) async {
    HomeTrendSettings.months = months;
    await settings.set(_homeTrendMonthsKey, months.toString());
    signalReload();
  }

  static Future<void> setActiveTemplateId(int id) async {
    activeTemplateId = id;
    await settings.set(_activeTemplateIdKey, id.toString());
    signalReload();
  }

  static Future<void> setHomeWidgetOrder(List<HomeLayoutItem> order) async {
    HomeLayoutSettings.order = order;
    await settings.set(
      _homeWidgetOrderKey,
      order.map((i) => i.token).join(','),
    );
    signalReload();
  }

  static Future<void> setMetricWidgetOrder(List<MetricLayoutItem> order) async {
    MetricLayoutSettings.order = order;
    await settings.set(
      _metricWidgetOrderKey,
      order.map((i) => i.token).join(','),
    );
    signalReload();
  }

  /// Turning dev mode off while the demo profile happens to be active
  /// switches back to personal immediately — no reason to leave a data set
  /// open that its own controls just disappeared for.
  static Future<void> setDevMode(bool enabled) async {
    devModeEnabled.value = enabled;
    await DevModeManager.setEnabled(enabled);
    if (!enabled && activeProfile.value == AppProfile.demo) {
      await switchProfile(AppProfile.personal);
    }
    signalReload();
  }
}
