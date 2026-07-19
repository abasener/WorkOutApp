import 'package:flutter/material.dart';

import '../services/user_profile.dart';
import 'onboarding/onboarding_flow.dart';
import 'root_shell.dart';

/// Top of the widget tree below `MaterialApp` — decides between the
/// onboarding survey and the normal app shell based on
/// `UserProfile.onboardingComplete` (resolved once at startup by
/// `AppServices.init`, and flipped back to false by
/// `AppServices.resetDemoDataToOnboarding` when previewing onboarding on the
/// demo profile). Re-pushed as a fresh route (`pushAndRemoveUntil`) by the
/// "Reset demo data" flow rather than relying on a rebuild, since the
/// decision only needs to be (re-)made at those two specific moments, not on
/// every frame.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return UserProfile.onboardingComplete
        ? const RootShell()
        : const OnboardingFlow();
  }
}
