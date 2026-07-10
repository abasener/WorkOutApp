import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';

/// Icon + short text "smart trend" card shown on Home.
/// Always shown when relevant; falls back to a neutral "all good" state.
/// No push notifications — in-app only, per designFiles/00_UX_DESIGN.md.
class StatusCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;

  const StatusCard({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor = AppColors.good,
  });

  factory StatusCard.allGood() => const StatusCard(
        icon: Icons.check_circle_outline,
        text: 'All good — nothing stands out right now.',
        iconColor: AppColors.good,
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: AppSpacing.standard),
          Expanded(child: Text(text, style: AppText.bodyText)),
        ],
      ),
    );
  }
}
