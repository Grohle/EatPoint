import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_profile_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Onboarding's "Your diet" step: allergies, intolerances and diet, all
/// optional. Saved with the rest once onboarding finishes.
class OnboardingDietPageBody extends StatefulWidget {
  final DietProfile initialProfile;
  final ValueChanged<DietProfile> onChanged;

  const OnboardingDietPageBody({
    super.key,
    this.initialProfile = DietProfile.empty,
    required this.onChanged,
  });

  @override
  State<OnboardingDietPageBody> createState() => _OnboardingDietPageBodyState();
}

class _OnboardingDietPageBodyState extends State<OnboardingDietPageBody> {
  late DietProfile _profile = widget.initialProfile;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Semantics(
      identifier: 'onboarding-diet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.onboardingDietTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Dimens.spacing8),
          Text(s.onboardingDietIntro, style: theme.textTheme.bodyMedium),
          DietProfileForm(
            profile: _profile,
            onChanged: (next) {
              setState(() => _profile = next);
              widget.onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}
