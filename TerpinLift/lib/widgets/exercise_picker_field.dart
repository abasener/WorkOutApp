import 'package:flutter/material.dart';

import '../data/models/exercise.dart';
import '../theme/app_theme.dart';

/// A searchable exercise dropdown: empty/untouched shows only [defaultOptions]
/// (typically pinned lifts, plus whatever's currently selected) so the
/// common case stays a short list, but typing searches [allOptions] by name
/// so anything in the full library is still reachable without leaving the
/// form. A clean middle ground between "pinned-only dropdown" (fast but
/// can't reach unpinned lifts) and "full ~75-exercise dropdown" (everything
/// reachable but slow to scan) — shows what matters first, lets you search
/// for the rest.
class ExercisePickerField extends StatelessWidget {
  final List<Exercise> allOptions;
  final List<Exercise> defaultOptions;
  final Exercise? selected;
  final ValueChanged<Exercise> onSelected;
  final String labelText;

  const ExercisePickerField({
    super.key,
    required this.allOptions,
    required this.defaultOptions,
    required this.selected,
    required this.onSelected,
    this.labelText = 'Exercise',
  });

  @override
  Widget build(BuildContext context) {
    // Keyed on the selected id so switching selection programmatically
    // (e.g. a fresh session load) re-seeds the field's own text instead of
    // Autocomplete's internal controller holding on to stale text.
    return Autocomplete<Exercise>(
      key: ValueKey(selected?.id),
      displayStringForOption: (e) => e.name,
      initialValue: TextEditingValue(text: selected?.name ?? ''),
      optionsBuilder: (value) {
        if (value.text.isEmpty) return defaultOptions;
        final q = value.text.toLowerCase();
        return allOptions.where((e) => e.name.toLowerCase().contains(q));
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        style: AppText.bodyText,
        decoration: InputDecoration(labelText: labelText),
      ),
      optionsViewBuilder: (context, onSelectedOption, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: AppColors.surfaceRaised,
          elevation: 4,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, minWidth: 200),
            child: options.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.standard),
                    child: Text('No matches', style: AppText.smallText),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final option = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(option.name, style: AppText.bodyText),
                        onTap: () => onSelectedOption(option),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
