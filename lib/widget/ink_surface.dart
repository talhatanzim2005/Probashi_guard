import 'package:flutter/material.dart';

/// A tappable card: [decoration] gives it its fill, border and shadow, and the
/// tap ripple is drawn *over* that fill, where it can be seen.
///
/// `InkWell(child: Container(decoration: BoxDecoration(color: ...)))` looks
/// right but shows no ripple: the ripple is painted on the nearest [Material]
/// above the [InkWell], which is underneath the container's colour. Here the
/// container is the outer widget and a transparent [Material] sits inside it, so
/// the ripple lands on top of the colour and is clipped to the corners.
///
/// Use it wherever a coloured card is tappable. A card that has no fill of its
/// own can use a plain [InkWell] inside a [Material] as usual.
class InkSurface extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Fill, border and shadow of the card.
  final Decoration? decoration;

  /// Corners the ripple is clipped to. Defaults to the decoration's own.
  final BorderRadius? borderRadius;

  /// Space between the card's edge and [child]; the ripple covers it too.
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxConstraints? constraints;
  final double? width;
  final double? height;

  /// When set, fill, border and size change smoothly over this long (e.g. a
  /// pill that lights up when selected).
  final Duration? duration;
  final Curve curve;

  /// Places [child] inside the card (e.g. centred in a fixed-height tile).
  final AlignmentGeometry? alignment;

  final Color? splashColor;

  const InkSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.decoration,
    this.borderRadius,
    this.padding,
    this.margin,
    this.constraints,
    this.width,
    this.height,
    this.duration,
    this.curve = Curves.linear,
    this.alignment,
    this.splashColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ??
        (decoration is BoxDecoration
            ? (decoration as BoxDecoration).borderRadius as BorderRadius?
            : null);

    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    if (alignment != null) {
      content = Align(alignment: alignment!, child: content);
    }

    final ink = Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: radius == null ? Clip.none : Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        splashColor: splashColor,
        child: content,
      ),
    );

    final animated = duration;
    if (animated != null) {
      return AnimatedContainer(
        duration: animated,
        curve: curve,
        margin: margin,
        constraints: constraints,
        width: width,
        height: height,
        decoration: decoration,
        child: ink,
      );
    }
    return Container(
      margin: margin,
      constraints: constraints,
      width: width,
      height: height,
      decoration: decoration,
      child: ink,
    );
  }
}
