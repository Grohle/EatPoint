import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The EatPoint mark, in the variant that reads on the active Material theme
/// (not the system brightness: a user who forces dark mode while the device
/// is on light should see the dark variant, as in the About dialog).
class DynamicOntLogo extends StatelessWidget {
  const DynamicOntLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      Theme.of(context).brightness == Brightness.light
          ? 'assets/icon/eatpoint_mark.svg'
          : 'assets/icon/eatpoint_mark_dark.svg',
    );
  }
}
