import 'package:flutter/material.dart';

import '../platform/desktop.dart';
import 'design.dart';

/// Marks the inside of a floating sheet: its pages leave no room for window
/// controls, do not drag the window, and open their next step in the sheet.
class InSheet extends InheritedWidget {
  const InSheet({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InSheet>() != null;
  @override
  bool updateShouldNotify(InSheet oldWidget) => false;
}

/// Whether a page opens as a sheet over the window: a desktop wide enough to
/// keep the conversation visible around it.
bool sheetsOpen(BuildContext context) =>
    !context.tone.glass && MediaQuery.sizeOf(context).width >= 840;

/// Opens [page] as a floating sheet on a wide desktop and as a full page
/// elsewhere. A sheet that holds a form ([form]) closes only from its own
/// controls, so a stray click beside it cannot throw the typing away.
Future<T?> openPage<T>(BuildContext context, Widget page, {bool form = false}) {
  if (InSheet.of(context) || !sheetsOpen(context)) {
    return pushPage<T>(context, page);
  }
  return Navigator.of(context)
      .push<T>(SheetRoute<T>(page, first: true, form: form));
}

/// One step of a floating sheet. The first fades the window back and rises
/// into place, with a close button in its bar; later steps slide in within the
/// same frame, with a back button, and keep the window as it is.
class SheetRoute<T> extends PageRoute<T> {
  final Widget page;
  final bool first, form;
  SheetRoute(this.page, {required this.first, this.form = false})
    : super(fullscreenDialog: first);

  @override
  bool get opaque => false;
  @override
  bool get barrierDismissible => first && !form;
  @override
  Color? get barrierColor =>
      first ? Colors.black.withValues(alpha: .22) : Colors.transparent;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => Duration(milliseconds: first ? 220 : 200);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => SheetFrame(child: page);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (first) {
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween(begin: .97, end: 1.0).animate(curve),
          child: child,
        ),
      );
    }
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(.02, 0),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

/// The floating frame: rounded, lifted off the window by its shadow, sized to
/// read comfortably and never wider than the window allows.
class SheetFrame extends StatelessWidget {
  final Widget child;
  const SheetFrame({super.key, required this.child});
  static const radius = 18.0;
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 48).clamp(0.0, 760.0);
    final height = (size.height - 48).clamp(0.0, 780.0);
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            shadows: tone.lift,
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(radius),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(size: Size(width, height)),
                child: InSheet(child: WindowSheetScope(child: child)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
