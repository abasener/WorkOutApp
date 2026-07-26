import 'package:flutter/material.dart';

import '../../services/home_layout_settings.dart';
import '../../theme/app_theme.dart';

/// Settings for a single-instance Home widget (Muscle Status, Plan a
/// Session, Primed for Growth, Training Split, Checklist, HIIT) — just a
/// title override, since none of these have any other per-card setting
/// (designFiles/02_SCREEN_home.md "Home layout editing"). Reached via the
/// gear icon in edit mode; hide/show is its own direct eye-icon toggle, not
/// part of this sheet.
class HomeWidgetTitleSheet extends StatefulWidget {
  final String defaultTitle;
  final String? currentTitle;

  const HomeWidgetTitleSheet({
    super.key,
    required this.defaultTitle,
    required this.currentTitle,
  });

  @override
  State<HomeWidgetTitleSheet> createState() => _HomeWidgetTitleSheetState();
}

class _HomeWidgetTitleSheetState extends State<HomeWidgetTitleSheet> {
  late final _controller = TextEditingController(
    text: widget.currentTitle ?? widget.defaultTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    // Popped verbatim — a plain `null` is reserved for "dismissed without
    // saving," which the caller (`_HomeScreenState._resolveTitle`) needs to
    // tell apart from an explicit save. The caller also decides what an
    // empty string here means (explicitly blank, not "reset to default") —
    // this sheet doesn't collapse that itself, since it doesn't know
    // whether blank should map to null or '' in `HomeLayoutItem.title`.
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.defaultTitle} settings', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            Text('Title', style: AppText.label),
            const SizedBox(height: AppSpacing.small),
            TextField(
              controller: _controller,
              style: AppText.bodyText,
              maxLength: homeWidgetTitleMaxLength,
              decoration: InputDecoration(
                hintText: widget.defaultTitle,
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.standard),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
