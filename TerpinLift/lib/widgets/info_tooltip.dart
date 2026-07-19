import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Plain-language glossary text shown by [InfoTooltip].
/// Source of truth: designFiles/08_GLOSSARY_AND_SCIENCE.md — keep in sync.
class Glossary {
  static const Map<String, String> _entries = {
    'rpe':
        "Roughly how many reps you had left in the tank on that set, 0-10. "
        "0 = truly failed, tried one more and couldn't. Past about 8 it "
        "stops meaning much: 8, 9, and 10 left all just mean \"that "
        "barely did anything.\" This isn't about pain, just how close to "
        "your limit you were.",
    'soreness':
        'How sore an area is right now, on a 0-5 scale, independent of any '
        'specific lift. Used to judge recovery, not to compare against a '
        'specific workout.',
    'e1rm':
        "An estimate of your max single-rep lift, calculated from whatever "
        "reps/weight you actually did. Lets a 5-rep set and a 3-rep set at "
        "different weights compare fairly on the same scale.",
    'readiness':
        "This map shows which muscles are recovered and ready to train "
        "hard again.\n\nIt uses how recently you trained each muscle, "
        "current soreness, recent sleep, and whether your effort or "
        "lift numbers have been trending down to predict readiness.",
    'strength_goal':
        'A long-term target based on how your current best lift compares to '
        'commonly cited bodyweight-ratio strength standards (e.g. squat = '
        "some multiple of bodyweight), adjusted for gender and a broad age "
        "bracket. These are directional, generalized figures, not a "
        "personally measured standard, meant to help guide steady "
        "progress, not to say what you should be able to lift.",
    'predicted_1rm':
        "An estimate of your one-rep max, projected from your best of the "
        "last few sessions using an e1RM formula, not something you "
        "actually lifted. This is separate from your true max above, and "
        "it's based purely on your most recent history (no assumption "
        "about fading over time if you take a break from this lift), so "
        "treat it as a rough guide rather than a logged number. For the "
        "most accurate figure, test your actual 1RM on lifts you care "
        "about from time to time.",
    'next_heavy_set':
        "Looks at the rep count you actually tend to go heavy for on this "
        "lift, then projects a weight at that same rep count from your "
        "recent history at that rep count. No converting between rep "
        "ranges to get wrong, since it's not estimating a 1RM at all. "
        "The range narrows the more times you've logged a heavy set at "
        "that same rep count.",
    'strength_goal_bodyweight':
        'A long-term target based on your best plain-bodyweight rep count '
        '(no assistance, no added weight) against commonly cited rep-count '
        'standards for this movement, adjusted for gender and a broad age '
        "bracket. Assisted or weighted sets still count toward your "
        "Predicted Next range above, just not this rep-standard ladder. "
        "It's meant to stay comparable to the published numbers it's "
        "based on.",
  };

  static String textFor(String key) =>
      _entries[key] ?? 'No description available.';
}

/// Small circled "i" that opens a plain-language explanation on tap.
/// Reused anywhere a term (RPE, soreness, e1RM, ...) needs a definition.
class InfoTooltip extends StatelessWidget {
  final String glossaryKey;
  final String? title;

  /// Extra content shown below the glossary text — e.g. the readiness map's
  /// color-band legend, which lives here instead of cluttering Home itself.
  final Widget? footer;

  const InfoTooltip({
    super.key,
    required this.glossaryKey,
    this.title,
    this.footer,
  });

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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title ?? glossaryKey.toUpperCase(), style: AppText.subHeader),
            const SizedBox(height: AppSpacing.small),
            Text(Glossary.textFor(glossaryKey), style: AppText.bodyText),
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.large),
              footer!,
            ],
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
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
