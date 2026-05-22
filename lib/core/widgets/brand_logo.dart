import 'package:flutter/material.dart';

/// The app's wordless logo — a black graduation cap over the violet-to-
/// green brand gradient — rendered with consistent rounded corners.
///
/// One widget for every in-app placement (sidebar tile, About card, etc.)
/// so a future logo refresh only needs to change the asset path here, and
/// every surface picks the new artwork up automatically.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 44,
    this.borderRadius,
  });

  /// Edge length of the (square) logo tile in logical pixels.
  final double size;

  /// Optional override for the corner radius. Defaults to a quarter of
  /// [size], which matches the rounded-square shape Material uses for
  /// app icons at this scale.
  final double? borderRadius;

  static const _assetPath = 'assets/Images/logo/CampusBuddy Logo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius ?? size / 4),
      child: Image.asset(
        _assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The image embeds its own gradient background — render it 1:1
        // and disable Flutter's auto-filtering so the sharp edges of the
        // cap stay crisp at small sizes.
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
