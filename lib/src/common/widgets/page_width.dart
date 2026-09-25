import 'package:flutter/widgets.dart';

/// Comfortable maximum widths for page content.
///
/// The app was laid out for a phone, where every screen is naturally narrow.
/// On a 13" iPad the same widgets stretch to ~1030pt: buttons run the whole
/// bezel-to-bezel width and body text reaches line lengths nobody can read.
/// These caps keep each screen at phone-ish proportions and centre it.
///
/// Values follow the usual typographic guidance — roughly 60–75 characters per
/// line for prose, and a form no wider than it needs to be.
const double kFormWidth = 480;
const double kContentWidth = 720;

/// Centres [child] and caps how wide it may grow.
///
/// Below [maxWidth] this is a no-op, so phone layouts are untouched.
class PageWidth extends StatelessWidget {
  const PageWidth({
    super.key,
    required this.child,
    this.maxWidth = kContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
