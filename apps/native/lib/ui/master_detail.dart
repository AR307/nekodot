import 'package:flutter/material.dart';

import '../platform/desktop.dart';
import 'design.dart';

/// A list on the left and, beside it, what its rows open. Where there is not
/// room for both, it is only the list, and a row opens as a page of its own.
///
/// Rows need no change for this: under a [MasterDetail] with room, `pushPage`
/// shows the page beside the list instead of over it.
class MasterDetail extends StatefulWidget {
  final Widget master;
  final double masterWidth;

  /// What stands beside the list before a row is chosen.
  final Widget? initial;
  const MasterDetail({
    super.key,
    required this.master,
    this.masterWidth = 320,
    this.initial,
  });

  /// The pane that takes pages opened from [context], when there is one.
  static MasterDetailState? paneOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ListSide>()?.pane;

  @override
  State<MasterDetail> createState() => MasterDetailState();
}

class MasterDetailState extends State<MasterDetail> {
  final _detail = GlobalKey<NavigatorState>();

  /// Shows [page] beside the list, in place of what was there. The future
  /// completes when the page closes or is replaced, as a pushed page's does
  /// when it is popped.
  Future<T?> show<T>(Widget page) => _detail.currentState!
      .pushAndRemoveUntil<T>(_DetailRoute<T>(page), (route) => route.isFirst);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final tone = context.tone;
      final room = !tone.glass && box.maxWidth >= widget.masterWidth + 400;
      if (!room) return widget.master;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: widget.masterWidth,
            child: _ListSide(pane: this, child: widget.master),
          ),
          VerticalDivider(
            width: Tone.hair,
            thickness: Tone.hair,
            color: tone.line,
          ),
          Expanded(
            // The pane is inside the window, away from its controls.
            child: WindowSheetScope(
              child: ClipRect(
                child: Navigator(
                  key: _detail,
                  onGenerateInitialRoutes: (navigator, _) => [
                    PageRouteBuilder<void>(
                      pageBuilder: (context, _, _) =>
                          ColoredBox(color: context.tone.base),
                    ),
                    if (widget.initial != null)
                      _DetailRoute<void>(widget.initial!),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ListSide extends InheritedWidget {
  final MasterDetailState pane;
  const _ListSide({required this.pane, required super.child});
  @override
  bool updateShouldNotify(_ListSide oldWidget) => pane != oldWidget.pane;
}

/// What a row opened: it stands beside the list, so it has nowhere to go back
/// to and shows no back button.
class _DetailRoute<T> extends MaterialPageRoute<T> {
  _DetailRoute(Widget page) : super(builder: (_) => page);
  @override
  bool get impliesAppBarDismissal => false;
}
