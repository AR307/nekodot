import 'package:flutter/material.dart';

import '../platform/desktop.dart';
import 'design.dart';

/// A list on the left and, beside it, what its rows open. Where there is not
/// room for both, it is only the list, and a row opens as a page of its own.
///
/// Rows open their page as anywhere else: under a [MasterDetail] with room,
/// `pushPage` shows the page beside the list instead of over it. A row that
/// names itself there (`row:`) can ask [shows] whether it is the one open,
/// to mark itself.
class MasterDetail extends StatefulWidget {
  final Widget master;
  final double masterWidth;

  /// What stands beside the list before a row is chosen, and the row it
  /// belongs to.
  final Widget? initial;
  final Object? initialRow;
  const MasterDetail({
    super.key,
    required this.master,
    this.masterWidth = 320,
    this.initial,
    this.initialRow,
  });

  /// The pane that takes pages opened from [context], when there is one.
  static MasterDetailState? paneOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ListSide>()?.pane;

  /// Whether the page of [row] is the one beside the list. The row is built
  /// again when that changes.
  static bool shows(BuildContext context, Object row) =>
      context
          .dependOnInheritedWidgetOfExactType<_ListSide>()
          ?.notifier
          ?.value ==
      row;

  @override
  State<MasterDetail> createState() => MasterDetailState();
}

class MasterDetailState extends State<MasterDetail> {
  final _detail = GlobalKey<NavigatorState>();
  late final _shown = ValueNotifier<Object?>(widget.initialRow);
  Route<Object?>? _route;

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  /// Shows [page] beside the list, in place of what was there, and marks
  /// [row] as the one open. The future completes when the page closes or is
  /// replaced, as a pushed page's does when it is popped.
  Future<T?> show<T>(Widget page, {Object? row}) async {
    final route = _DetailRoute<T>(page);
    _route = route;
    _shown.value = row;
    final result = await _detail.currentState!.pushAndRemoveUntil<T>(
      route,
      (route) => route.isFirst,
    );
    // Closed rather than replaced: nothing is open any more.
    if (identical(_route, route) && mounted) {
      _route = null;
      _shown.value = null;
    }
    return result;
  }

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
            child: _ListSide(
              pane: this,
              notifier: _shown,
              child: widget.master,
            ),
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

class _ListSide extends InheritedNotifier<ValueNotifier<Object?>> {
  final MasterDetailState pane;
  const _ListSide({
    required this.pane,
    required super.notifier,
    required super.child,
  });
}

/// What a row opened: it stands beside the list, so it has nowhere to go back
/// to and shows no back button.
class _DetailRoute<T> extends MaterialPageRoute<T> {
  _DetailRoute(Widget page) : super(builder: (_) => page);
  @override
  bool get impliesAppBarDismissal => false;
}
