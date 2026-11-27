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

  /// Whether to download the food database once onboarding ends; null
  /// hides the switch.
  final bool? initialDownloadFoodDb;
  final ValueChanged<bool>? onDownloadFoodDbChanged;

  const OnboardingDietPageBody({
    super.key,
    this.initialProfile = DietProfile.empty,
    required this.onChanged,
    this.initialDownloadFoodDb,
    this.onDownloadFoodDbChanged,
  });

  @override
  State<OnboardingDietPageBody> createState() => _OnboardingDietPageBodyState();
}

class _OnboardingDietPageBodyState extends State<OnboardingDietPageBody> {
  late DietProfile _profile = widget.initialProfile;
  late bool? _downloadFoodDb = widget.initialDownloadFoodDb;

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
          if (_downloadFoodDb case final download?) ...[
            const SizedBox(height: Dimens.spacing16),
            Semantics(
              identifier: 'onboarding-food-db',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.storage_rounded),
                title: Text(s.foodDbOnboardingTitle),
                subtitle: Text(s.foodDbOnboardingBody),
                value: download,
                onChanged: (v) {
                  setState(() => _downloadFoodDb = v);
                  widget.onDownloadFoodDbChanged?.call(v);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
