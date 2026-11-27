import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// First screen shown on launch: the EatPoint mark builds itself — the "e"
/// scales in with a slight overshoot, its leaf crossbar grows out from the
/// left, the amber dot pops into place and the wordmark fades up beneath.
/// It then routes on to the main screen (returning user) or onboarding
/// (first run).
///
/// The native launch screen (Android `launch_background`, iOS
/// `LaunchScreen.storyboard`) paints the same canvas colour behind the Flutter
/// engine while it boots, so the hand-off into this animated splash is seamless.
class SplashScreen extends StatefulWidget {
  /// Whether the user has already completed onboarding. Decides where the
  /// splash routes once the animation finishes.
  final bool userInitialized;

  const SplashScreen({super.key, required this.userInitialized});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoSize = 152.0;
  static const _startDelay = Duration(milliseconds: 150);
  static const _animationDuration = Duration(milliseconds: 1600);

  // Dot centre inside the 120x120 layer SVGs, as an Alignment (-1..1).
  static const _dotAlignment = Alignment(0.627, 0.287);
  // The leaf is anchored near its left tip so it grows out of the "e".
  static const _leafAlignment = Alignment(-0.633, 0.0);

  late final AnimationController _controller;
  late final Animation<double> _eScale;
  late final Animation<double> _eFade;
  late final Animation<double> _eTurn;
  late final Animation<double> _leafGrow;
  late final Animation<double> _dotScale;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordSlide;
  Timer? _startTimer;
  bool _navigated = false;

  Animation<double> _interval(double begin, double end, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: curve),
      );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    _eScale = Tween<double>(
      begin: 0.55,
      end: 1.0,
    ).animate(_interval(0.0, 0.40, Curves.easeOutBack));
    _eFade = _interval(0.0, 0.20, Curves.easeOut);
    _eTurn = Tween<double>(
      begin: -0.06,
      end: 0.0,
    ).animate(_interval(0.0, 0.40, Curves.easeOutCubic));
    _leafGrow = _interval(0.30, 0.58, Curves.easeOutCubic);
    _dotScale = _interval(0.52, 0.76, Curves.easeOutBack);
    _wordFade = _interval(0.66, 0.90, Curves.easeOut);
    _wordSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(_interval(0.66, 0.90, Curves.easeOutCubic));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });

    // Honour the OS "reduce motion" setting: show the finished mark and move on.
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) {
      _controller.value = 1.0;
      _startTimer = Timer(const Duration(milliseconds: 600), _goNext);
    } else {
      // A short beat on the empty canvas before the mark builds itself.
      _startTimer = Timer(_startDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(
      widget.userInitialized
          ? NavigationOptions.mainRoute
          : NavigationOptions.onboardingRoute,
    );
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _layer(String name, {SvgTheme theme = const SvgTheme()}) =>
      SvgPicture.asset(
        'assets/icon/eatpoint_splash_$name.svg',
        width: _logoSize,
        height: _logoSize,
        theme: theme,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The "e" follows the theme like the in-app logo: deep green on the light
    // canvas, near-white on the dark canvas.
    final eColor = isDark ? const Color(0xFFF3FFF5) : const Color(0xFF0E2A1A);
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _logoSize,
              height: _logoSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FadeTransition(
                    opacity: _leafGrow,
                    child: ScaleTransition(
                      scale: _leafGrow,
                      alignment: _leafAlignment,
                      child: _layer('leaf'),
                    ),
                  ),
                  FadeTransition(
                    opacity: _eFade,
                    child: RotationTransition(
                      turns: _eTurn,
                      child: ScaleTransition(
                        scale: _eScale,
                        child: _layer(
                          'e',
                          theme: SvgTheme(currentColor: eColor),
                        ),
                      ),
                    ),
                  ),
                  ScaleTransition(
                    scale: _dotScale,
                    alignment: _dotAlignment,
                    child: _layer('dot'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: _wordFade,
              child: SlideTransition(
                position: _wordSlide,
                child: Text(
                  S.of(context).appTitle,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
