import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Plain-language glossary text shown by [InfoTooltip].
/// Source of truth: designFiles/08_GLOSSARY_AND_SCIENCE.md — keep in sync.
class Glossary {
  static const Map<String, String> _entries = {
    'rpe':
        "How hard that set felt, 1-10. 10 = you couldn't have done another rep. "
            "7 = you probably had about 3 more reps in you. Lower numbers = an "
            "easier/recovery-style set. This isn't about pain, just effort.",
    'soreness':
        'How sore an area is right now, on a 0-5 scale, independent of any '
            'specific lift. Used to judge recovery, not to compare against a '
            'specific workout.',
    'e1rm':
        "An estimate of your max single-rep lift, calculated from whatever "
            "reps/weight you actually did. Lets a 5-rep set and a 3-rep set at "
            "different weights compare fairly on the same scale.",
    'readiness':
        "How ready each muscle looks to be trained hard again, blending a "
            "few things: how long it's been since you last trained it (bigger "
            "muscle groups like legs and back get a longer recovery window "
            "than smaller ones like arms, based on typical strength-training "
            "recovery guidance), how sore that area currently is, your recent "
            "sleep, whether your effort (RPE) has been creeping up there "
            "lately, and whether your lift numbers for it have dipped "
            "against your recent average. Greener = more ready, dimmer = "
            "still recovering. It's a heuristic blend of real training-"
            "science signals, not a lab measurement of your actual muscles.",
    'strength_goal':
        'A long-term target based on how your current best lift compares to '
            'commonly cited bodyweight-ratio strength standards (e.g. squat = '
            "some multiple of bodyweight), adjusted for gender and a broad age "
            "bracket. These are directional, generalized figures — not a "
            "personally measured standard — meant to help guide steady "
            "progress, not to say what you should be able to lift.",
  };

  static String textFor(String key) =>
      _entries[key] ?? 'No description available.';
}

/// Small circled "i" that opens a plain-language explanation on tap.
/// Reused anywhere a term (RPE, soreness, e1RM, ...) needs a definition.
class InfoTooltip extends StatelessWidget {
  final String glossaryKey;
  final String? title;

  const InfoTooltip({super.key, required this.glossaryKey, this.title});

  void _show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.large,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title ?? glossaryKey.toUpperCase(), style: AppText.subHeader),
            const SizedBox(height: AppSpacing.small),
            Text(Glossary.textFor(glossaryKey), style: AppText.bodyText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.micro),
        child: Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}
