import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/user_profile.dart';
import '../../theme/app_theme.dart';
import '../root_shell.dart';

/// First-run survey — two short pages (welcome, then gender/birth year/
/// starting weight), landing on `AppServices.completeOnboarding`. Shown by
/// `AppRoot` whenever `UserProfile.onboardingComplete` is false: a genuinely
/// fresh install, or the demo profile right after "Reset demo data" (see
/// `AppServices.resetDemoDataToOnboarding`) — the same screen serves both,
/// it just writes into whichever profile is currently active.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  int _page = 0;
  Gender _gender = Gender.female;
  // Birth year defaults to a plausible starting point rather than blank —
  // weight deliberately does NOT get an equivalent default (the user's own
  // call: suggesting a starting weight felt wrong), it's just required to
  // be filled in like every other field on this page.
  final _birthYearController = TextEditingController(text: '2000');
  final _weightController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Both fields gate the "Get Started" button — rebuild on every
    // keystroke so it can flip from disabled to tappable as soon as the
    // last one is filled in.
    _birthYearController.addListener(_onFieldChanged);
    _weightController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  bool get _canProceed {
    if (_page == 0) return true;
    final year = int.tryParse(_birthYearController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final validYear =
        year != null && year >= 1900 && year <= DateTime.now().year;
    final validWeight = weight != null && weight > 0;
    return validYear && validWeight;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _birthYearController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page == 0) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    final currentYear = DateTime.now().year;
    final enteredYear = int.tryParse(_birthYearController.text.trim());
    final birthYear =
        (enteredYear != null &&
            enteredYear >= 1900 &&
            enteredYear <= currentYear)
        ? enteredYear
        : null;
    final enteredWeight = double.tryParse(_weightController.text.trim());
    final startingWeightLb = (enteredWeight != null && enteredWeight > 0)
        ? enteredWeight
        : null;

    await AppServices.completeOnboarding(
      gender: _gender,
      birthYear: birthYear,
      startingWeightLb: startingWeightLb,
    );

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const RootShell()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          // Next-button driven, not a swipeable carousel — keeps the flow
          // linear and matches "welcome page, then a page to enter info."
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            const _WelcomePage(),
            _ProfilePage(
              gender: _gender,
              onGenderChanged: (g) => setState(() => _gender = g),
              birthYearController: _birthYearController,
              weightController: _weightController,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceed
                    ? AppColors.accent
                    : AppColors.surfaceRaised,
                foregroundColor: _canProceed
                    ? Colors.white
                    : AppColors.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              onPressed: (_saving || !_canProceed) ? null : _next,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_page == 0 ? 'Next' : 'Get Started'),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The app's own turtle-with-dumbbells mark (same source
          // flutter_launcher_icons uses) rather than a generic icon — a
          // raised circular backdrop keeps its black shell visible against
          // the near-black app background instead of disappearing into it.
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: Image.asset('assets/icon/foreground.png'),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Welcome to TerrapinLift', style: AppText.pageHeader),
          const SizedBox(height: AppSpacing.standard),
          Text(
            'A personal strength and recovery tracker. It shows you what your '
            'own logged data says, plain and simple, so you can decide what to '
            'do with it.',
            style: AppText.bodyText,
          ),
          const SizedBox(height: AppSpacing.large),
          _bullet('Log lifts, cardio, and HIIT circuits'),
          _bullet('See recovery and readiness at a glance'),
          _bullet('Track steps, sleep, soreness, and weight over time'),
          const SizedBox(height: AppSpacing.large),
          Text(
            'Everything stays on this device. A couple of quick questions '
            'first, then you\'re in.',
            style: AppText.smallText,
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.small),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(child: Text(text, style: AppText.bodyText)),
      ],
    ),
  );
}

class _ProfilePage extends StatelessWidget {
  final Gender gender;
  final ValueChanged<Gender> onGenderChanged;
  final TextEditingController birthYearController;
  final TextEditingController weightController;

  const _ProfilePage({
    required this.gender,
    required this.onGenderChanged,
    required this.birthYearController,
    required this.weightController,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A bit about you', style: AppText.pageHeader),
          const SizedBox(height: AppSpacing.small),
          Text(
            'Used for strength-standard goals and recovery timing. Nothing '
            'here is shared or shown anywhere else, and you can always '
            'change it later in Settings.',
            style: AppText.smallText,
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Gender', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          Row(
            children: [
              _genderChip('Female', Gender.female),
              const SizedBox(width: AppSpacing.small),
              _genderChip('Male', Gender.male),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Birth year', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          TextField(
            controller: birthYearController,
            keyboardType: TextInputType.number,
            style: AppText.bodyText,
            decoration: const InputDecoration(hintText: 'e.g. 1998'),
          ),
          const SizedBox(height: AppSpacing.large),
          Text('Starting weight', style: AppText.label),
          const SizedBox(height: AppSpacing.small),
          TextField(
            controller: weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: const InputDecoration(hintText: 'Weight in lb'),
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            'A rough estimate is fine to start. You can log it more '
            'precisely any time from Metrics.',
            style: AppText.smallText,
          ),
        ],
      ),
    );
  }

  Widget _genderChip(String label, Gender value) {
    final selected = gender == value;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        labelStyle: AppText.bodyText.copyWith(
          color: selected ? AppColors.accent : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        backgroundColor: AppColors.surfaceRaised,
        selectedColor: AppColors.accent.withValues(alpha: 0.15),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
        onSelected: (_) => onGenderChanged(value),
      ),
    );
  }
}
