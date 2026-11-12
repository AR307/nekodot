import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'design.dart';

/// Quotes the actual selected text, using Flutter's selection anchors.
class MessageSelection extends StatefulWidget {
  final Widget child;
  final String quoteLabel;
  final ValueChanged<String>? onQuote;
  const MessageSelection({
    super.key,
    required this.child,
    required this.quoteLabel,
    this.onQuote,
  });

  @override
  State<MessageSelection> createState() => _MessageSelectionState();
}

class _MessageSelectionState extends State<MessageSelection> {
  final _area = GlobalKey<SelectionAreaState>();
  final _focus = FocusNode();
  final _menu = ContextMenuController();
  ValueListenable<SelectableRegionSelectionStatus>? _status;
  ScrollPosition? _scroll;
  String _selected = '';
  bool _mouseSelection = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_dismiss);
      _scroll = scroll;
      _scroll?.addListener(_dismiss);
    }
    _dismiss();
  }

  void _dismiss() => _menu.remove();

  void _focusChanged() {
    if (!_focus.hasFocus) _dismiss();
  }

  void _quote() {
    final words = _selected;
    _dismiss();
    _area.currentState?.selectableRegion
      ?..hideToolbar()
      ..clearSelection();
    if (words.trim().isNotEmpty) widget.onQuote?.call(words);
  }

  void _selectionStatusChanged() {
    _dismiss();
    if (_status?.value != SelectableRegionSelectionStatus.finalized) return;
    // The last selection geometry is laid out after the release gesture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_mouseSelection ||
          !_focus.hasFocus ||
          widget.onQuote == null ||
          _selected.trim().isEmpty ||
          _status?.value != SelectableRegionSelectionStatus.finalized) {
        return;
      }
      final region = _area.currentState!.selectableRegion;
      final anchors = region.contextMenuAnchors;
      _menu.show(
        context: context,
        contextMenuBuilder: (context) => TapRegion(
          onTapOutside: (_) => _dismiss(),
          child: TextSelectionToolbar(
            anchorAbove: anchors.primaryAnchor,
            anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
            toolbarBuilder: (context, child) =>
                MenuEntrance(child: MenuCard(child: child)),
            children: [
              TextButton.icon(
                key: const ValueKey('selection-quote-bubble'),
                onPressed: _quote,
                icon: const Icon(Icons.format_quote_rounded, size: 18),
                label: Text(widget.quoteLabel),
                style: TextButton.styleFrom(
                  minimumSize: Size(48, context.tone.glass ? 48 : 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _dismiss();
    _status?.removeListener(_selectionStatusChanged);
    _scroll?.removeListener(_dismiss);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _dismiss();
      _mouseSelection =
          event.kind == PointerDeviceKind.mouse &&
          event.buttons == kPrimaryMouseButton;
    },
    child: SelectionArea(
      key: _area,
      focusNode: _focus,
      onSelectionChanged: (value) {
        _selected = value?.plainText ?? '';
        if (_selected.trim().isEmpty) _dismiss();
      },
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: [
              if (widget.onQuote != null && _selected.trim().isNotEmpty)
                ContextMenuButtonItem(
                  label: widget.quoteLabel,
                  onPressed: _quote,
                ),
              ...state.contextMenuButtonItems,
            ],
          ),
      child: Builder(
        builder: (context) {
          final status = SelectableRegionSelectionStatusScope.maybeOf(context);
          if (_status != status) {
            _status?.removeListener(_selectionStatusChanged);
            _status = status;
            _status?.addListener(_selectionStatusChanged);
          }
          return widget.child;
        },
      ),
    ),
  );
}
