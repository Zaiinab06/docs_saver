import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'personalize_screen.dart';

class _SlideData {
  final String image;
  final String title;
  final String subtitle;

  const _SlideData({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Design Tokens
  static const Color primaryColor = AppColors.primary;
  static const LinearGradient primaryGradient = AppColors.primaryGradient;
  static const Color backgroundColor = AppColors.cardBackground;
  static const Color textSecondaryColor = AppColors.textSecondary;
  static const Color pillInactiveColor = AppColors.border;
  static const Color pillActiveColor = primaryColor;

  static const List<_SlideData> _slides = [
    _SlideData(
      image: 'assets/images/onboarding1.png',
      title: 'Save anything',
      subtitle:
          'Capture links, voice notes, images, and text — all in one place.',
    ),
    _SlideData(
      image: 'assets/images/onboarding2.png',
      title: 'Connect the dots',
      subtitle:
          'Your ideas surface connections you never noticed before.',
    ),
    _SlideData(
      image: 'assets/images/onboarding3.png',
      title: 'Find it by meaning',
      subtitle:
          'Search by concept, feeling, or context — not just keywords.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToPersonalize() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PersonalizeScreen(),
      ),
    );
  }

  void _onNextPressed() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _navigateToPersonalize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Skip Button (Fixed position)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Visibility(
                      visible: _currentPage < _slides.length - 1,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: _navigateToPersonalize,
                        style: TextButton.styleFrom(
                          foregroundColor: textSecondaryColor,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Carousel with Reusable Slide Component
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return _OnboardingSlide(
                    imagePath: slide.image,
                    title: slide.title,
                    subtitle: slide.subtitle,
                  );
                },
              ),
            ),

            // Bottom Area: Page Indicator & Action Button (Fixed position)
            Padding(
              padding: const EdgeInsets.fromLTRB(28.0, 0, 28.0, 28.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page Indicator: Active smooth pill (24x6) and inactive dots (6x6)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) {
                        final isActive = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 3.0),
                          height: 6,
                          width: isActive ? 24 : 6,
                          decoration: BoxDecoration(
                            color: isActive ? pillActiveColor : pillInactiveColor,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Bottom Action Button: Full pill with Primary Gradient
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: primaryGradient,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _onNextPressed,
                        borderRadius: BorderRadius.circular(100),
                        child: Center(
                          child: Text(
                            _currentPage == _slides.length - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Normalized illustration bounds data calculated from the exact non-transparent
/// alpha bounds of each onboarding asset.
class _IllustrationBounds {
  final double canvasWidth;
  final double canvasHeight;
  final double contentMinX;
  final double contentMaxX;
  final double contentMinY;
  final double contentMaxY;
  final double scaleMultiplier;

  const _IllustrationBounds({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.contentMinX,
    required this.contentMaxX,
    required this.contentMinY,
    required this.contentMaxY,
    this.scaleMultiplier = 1.0,
  });

  double get visibleWidth => contentMaxX - contentMinX + 1.0;
  double get visibleHeight => contentMaxY - contentMinY + 1.0;

  double get contentCenterX => (contentMinX + contentMaxX) / 2.0;
  double get contentCenterY => (contentMinY + contentMaxY) / 2.0;

  // Normalized shift from canvas center to content center in canvas coordinate space
  double get dx => contentCenterX - (canvasWidth / 2.0);
  double get dy => contentCenterY - (canvasHeight / 2.0);

  // Scale factor so that rendered visible height equals targetFraction * containerHeight * scaleMultiplier
  double scaleFor(double targetFraction) =>
      targetFraction * (canvasHeight / visibleHeight) * scaleMultiplier;
}

/// A shared, visually normalized illustration widget for onboarding screens.
/// It inspects the actual non-transparent visible-content bounds of each asset
/// and applies a normalized per-image scale and translation so all illustrations
/// have the exact same rendered visual height, horizontal scale, and vertical alignment.
class OnboardingIllustration extends StatelessWidget {
  final String imagePath;
  final double? height;

  const OnboardingIllustration({
    super.key,
    required this.imagePath,
    this.height,
  });

  // Measured visible-content bounds from PNG alpha inspection:
  // onboarding1.png: canvas 1148x1371, content X [0, 1138], Y [115, 1309] (1139x1195)
  // onboarding2.png: canvas 1376x1143, content X [65, 1343], Y [6, 1126] (1279x1121)
  // onboarding3.png: canvas 1376x1143, content X [113, 1345], Y [69, 1142] (1233x1074)
  static const Map<String, _IllustrationBounds> _assetBounds = {
    'assets/images/onboarding1.png': _IllustrationBounds(
      canvasWidth: 1148,
      canvasHeight: 1371,
      contentMinX: 0,
      contentMaxX: 1138,
      contentMinY: 115,
      contentMaxY: 1309,
      scaleMultiplier: 1.09, // +9% size adjustment to match visual footprint with Screens 2 & 3
    ),
    'assets/images/onboarding2.png': _IllustrationBounds(
      canvasWidth: 1376,
      canvasHeight: 1143,
      contentMinX: 65,
      contentMaxX: 1343,
      contentMinY: 6,
      contentMaxY: 1126,
    ),
    'assets/images/onboarding3.png': _IllustrationBounds(
      canvasWidth: 1376,
      canvasHeight: 1143,
      contentMinX: 113,
      contentMaxX: 1345,
      contentMinY: 69,
      contentMaxY: 1142,
    ),
  };

  // Target visible content height as a fraction of container height (82%)
  // This guarantees identical visual height and identical top/bottom bounds.
  static const double targetVisibleFraction = 0.82;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight =
        height ?? MediaQuery.of(context).size.height * 0.32;
    final bounds = _assetBounds[imagePath];

    final double scale = bounds != null
        ? bounds.scaleFor(targetVisibleFraction)
        : 1.0;

    final double pixelScale = bounds != null
        ? (effectiveHeight * scale) / bounds.canvasHeight
        : 1.0;

    final double shiftX = bounds != null ? -bounds.dx * pixelScale : 0.0;
    final double shiftY = bounds != null ? -bounds.dy * pixelScale : 0.0;

    return SizedBox(
      height: effectiveHeight,
      width: double.infinity,
      child: Center(
        child: Transform.translate(
          offset: Offset(shiftX, shiftY),
          child: Transform.scale(
            scale: scale,
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: effectiveHeight * 0.7,
                  width: effectiveHeight * 0.7,
                  decoration: BoxDecoration(
                    color: AppColors.softLavenderBackground,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable Slide Component guaranteeing exact visual uniformity across all slides
class _OnboardingSlide extends StatelessWidget {
  final String imagePath;
  final String title;
  final String subtitle;

  const _OnboardingSlide({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final illustrationHeight = MediaQuery.of(context).size.height * 0.32;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shared illustration container with normalized visual footprint
        OnboardingIllustration(
          imagePath: imagePath,
          height: illustrationHeight,
        ),

        // Locked vertical gap below illustration container
        const SizedBox(height: 32),

        // Title: fixed-height container ensuring rock-solid baseline lock across slides
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ),

        // Locked vertical gap between title and subtitle
        const SizedBox(height: 12),

        // Subtitle: fixed-height container ensuring zero vertical shift across page transitions
        SizedBox(
          height: 44,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF8A8A8A),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
