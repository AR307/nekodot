import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A spring named by how long it feels and how much it bounces, usable wherever
/// a [Curve] and a [Duration] are. The curve runs the spring until it has
/// settled, so [duration] is longer than the felt length; it passes above 1
/// on the way, which is the overshoot.
class Spring extends Curve {
  /// Felt length in milliseconds.
  final int feel;

  /// 0 settles without passing its target; .3 passes it clearly.
  final double bounce;
  const Spring(this.feel, this.bounce);

  double get _damping => 1 - bounce;
  double get _rate => 2 * math.pi / feel;

  /// Until the motion is within a thousandth of rest.
  Duration get duration =>
      Duration(milliseconds: (math.log(1000) / (_damping * _rate)).round());

  @override
  double transformInternal(double t) {
    final time = t * duration.inMilliseconds, damping = _damping, rate = _rate;
    if (damping >= 1) return 1 - math.exp(-rate * time) * (1 + rate * time);
    final swing = rate * math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-damping * rate * time) *
            (math.cos(swing * time) +
                damping * rate / swing * math.sin(swing * time));
  }
}

/// How things move: springs that pass their place a little and settle, lists
/// that arrive one row after another, and short plain exits. One place, so a
/// menu, a sheet and a message feel like the same product.
///
/// Opacity never follows a spring (it cannot pass 1); it eases in over the
/// first part of the same span with [fade].
abstract final class Motion {
  /// Menus and popovers, growing from what opened them.
  static const pop = Spring(240, .28);

  /// Sheets and dialogs in the middle of the window.
  static const sheet = Spring(320, .22);

  /// Panels that slide in from the side and cover what is under them.
  static const drawer = Spring(360, .14);

  /// Panels docked beside the conversation.
  static const side = Spring(320, .18);

  /// One view replaced by another in the same place.
  static const swap = Spring(300, .2);

  /// A message arriving.
  static const message = Spring(300, .3);

  /// A notice in the corner.
  static const toast = Spring(320, .25);

  /// A phone page pushed over the last one.
  static const push = Spring(360, .1);

  /// A sheet rising from the bottom of a phone.
  static const bottomSheet = Spring(360, .16);

  /// A marker or a row moving to its new place.
  static const move = Spring(320, .22);

  /// Height following its content.
  static const fold = Spring(280, .12);

  /// A box growing out of a smaller one.
  static const zoom = Spring(360, .16);

  /// A small mark confirming a change.
  static const tick = Spring(240, .3);

  /// Leaving is quicker than arriving and never speeds up on the way out.
  static const leave = Cubic(.23, 1, .32, 1);
  static const popLeave = Duration(milliseconds: 110);
  static const sheetLeave = Duration(milliseconds: 140);
  static const drawerLeave = Duration(milliseconds: 190);
  static const sideLeave = Duration(milliseconds: 150);
  static const swapLeave = Duration(milliseconds: 80);
  static const toastLeave = Duration(milliseconds: 150);
  static const pushLeave = Duration(milliseconds: 240);
  static const bottomSheetLeave = Duration(milliseconds: 210);

  /// Opacity over a spring's span: in by the first two fifths.
  static const fade = Interval(0, .4, curve: Cubic(.23, 1, .32, 1));

  /// Hover and pressed colours.
  static const tint = Duration(milliseconds: 80);

  /// Between one row of a list arriving and the next; no row waits longer
  /// than eight steps.
  static const stagger = Duration(milliseconds: 28);
  static Duration delay(int index) => stagger * math.min(index, 8);

  /// [parent] through a spring on the way in and a quick ease-out on the way
  /// back. A reverse curve is read backwards, hence the flip.
  static Animation<double> spring(Animation<double> parent, Spring curve) =>
      CurvedAnimation(
        parent: parent,
        curve: curve,
        reverseCurve: const FlippedCurve(leave),
      );

  /// Opacity for something moving on a spring; it never passes 1.
  static Animation<double> fadeIn(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: fade,
    reverseCurve: const FlippedCurve(leave),
  );

  /// Nothing moves when the system asks for less motion.
  static bool still(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
  static Duration span(BuildContext context, Spring spring) =>
      still(context) ? Duration.zero : spring.duration;
}
