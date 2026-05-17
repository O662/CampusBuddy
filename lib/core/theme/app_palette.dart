import 'package:flutter/material.dart';

/// Calm, relaxing palette built around deep twilight blues/violets with
/// soft pastel accents. Glassmorphism surfaces sit on top of the animated
/// gradient defined by [backgroundStops].
class AppPalette {
  AppPalette._();

  // Accents — soft and low-saturation so nothing feels harsh.
  static const Color lavender = Color(0xFFB39DDB);
  static const Color periwinkle = Color(0xFF8C9EFF);
  static const Color mint = Color(0xFF80CBC4);
  static const Color sky = Color(0xFF81D4FA);
  static const Color peach = Color(0xFFFFCDB2);
  static const Color rose = Color(0xFFF7A6C4);

  /// Primary brand accent used for selected nav items, buttons, focus rings.
  static const Color accent = periwinkle;

  // Text on the dark glass.
  static const Color textPrimary = Color(0xFFF3F0FF);
  static const Color textSecondary = Color(0xFFB9B6D6);
  static const Color textFaint = Color(0xFF7E7BA6);

  // Glass surface tints.
  static const Color glassFill = Color(0x1FFFFFFF); // ~12% white
  static const Color glassFillStrong = Color(0x33FFFFFF); // ~20% white
  static const Color glassStroke = Color(0x3DFFFFFF); // ~24% white
  static const Color glassShadow = Color(0x66000000);

  /// The set of colors the background gradient slowly drifts between.
  /// Each "frame" is a full-screen [LinearGradient]; the animated background
  /// cross-fades between consecutive frames.
  static const List<List<Color>> backgroundFrames = [
    [Color(0xFF1B1A38), Color(0xFF2C2150), Color(0xFF1B3A4B)],
    [Color(0xFF221A40), Color(0xFF34265E), Color(0xFF1F4858)],
    [Color(0xFF1A2240), Color(0xFF2A2A5E), Color(0xFF1F4F52)],
    [Color(0xFF1F1A3A), Color(0xFF3A2658), Color(0xFF21455B)],
  ];

  static const Color scaffoldBase = Color(0xFF15132B);

  /// Semantic colors for status chips, progress, charts.
  static const Color success = Color(0xFF7BD8A8);
  static const Color warning = Color(0xFFF2C879);
  static const Color danger = Color(0xFFF28B82);
  static const Color info = sky;

  /// A pleasant rotation of accent colors for courses / decks / chips.
  static const List<Color> categorySwatches = [
    periwinkle,
    mint,
    lavender,
    peach,
    sky,
    rose,
    success,
  ];

  static Color swatchFor(int seed) =>
      categorySwatches[seed.abs() % categorySwatches.length];
}
