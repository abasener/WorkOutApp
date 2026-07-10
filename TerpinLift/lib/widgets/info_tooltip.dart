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
        'How sore you are today, 1-10, independent of any specific lift. Used '
            'to judge recovery, not to compare against a specific workout.',
    'e1rm':
        "An estimate of your max single-rep lift, calculated from whatever "
            "reps/weight you actually did. Lets a 5-rep set and a 3-rep set at "
            "different weights compare fairly on the same scale.",
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
