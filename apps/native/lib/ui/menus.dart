import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

/// A null entry separates groups. Values remain owned by the calling feature.
class MenuAction<T> {
  final T value;
  final String label;
  final Key? key;
  final IconData? icon;
  final Widget? leading, trailing;
  final bool enabled, selected;
  const MenuAction({
    required this.value,
    required this.label,
    this.key,
    this.icon,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.selected = false,
  });
}

/// Appearance A, motion A3. Both platforms anchor menus to their trigger;
/// phone options keep their larger touch targets.
class ActionMenu<T> extends StatelessWidget {
  final String tooltip;
  final List<MenuAction<T>?> items;
  final ValueChanged<T> onSelected;
  final Widget? child, icon;
  final double width;
  final bool enabled, alignEnd;
  const ActionMenu({
    super.key,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.child,
    this.icon,
    this.width = 280,
    this.enabled = true,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final choices = items.whereType<MenuAction<T>>().where(
      (item) => item.enabled,
    );
    final initial =
        choices.where((item) => item.selected).firstOrNull ??
        choices.firstOrNull;
    return MenuPopover(
      width: width,
      alignEnd: alignEnd,
      menuBuilder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            if (item == null)
              Divider(
                height: 9,
                thickness: .5,
                indent: 12,
                endIndent: 12,
                color: context.tone.line,
              )
            else
              MenuChoice(
                key: item.key,
                label: item.label,
                leading:
                    item.leading ??
                    (item.icon == null ? null : Icon(item.icon, size: 18)),
                trailing: item.trailing,
                selected: item.selected,
                autofocus: identical(item, initial),
                onPressed: item.enabled
                    ? () {
                        close();
                        onSelected(item.value);
                      }
                    : null,
              ),
        ],
      ),
      builder: (context, toggle, focus) => child == null
          ? IconButton(
              tooltip: tooltip,
              focusNode: focus,
              onPressed: enabled ? toggle : null,
              icon: icon ?? const Icon(Symbols.more_horiz, size: 20),
            )
          : Tooltip(
              message: tooltip,
              child: InkWell(
                focusNode: focus,
                onTap: enabled ? toggle : null,
                customBorder: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: child,
              ),
            ),
    );
  }
}

class MenuChoice extends StatelessWidget {
  final String label;
  final Widget? leading, trailing;
  final bool selected, autofocus;
  final VoidCallback? onPressed;
  const MenuChoice({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.selected = false,
    this.autofocus = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return MenuItemButton(
      autofocus: autofocus,
      overflowAxis: Axis.vertical,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(double.infinity, tone.glass ? 48 : 36),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(10)),
        ),
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              selected ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? tone.hover
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? tone.ink3 : tone.ink,
        ),
        overlayColor: WidgetStatePropertyAll(tone.ink.withValues(alpha: .05)),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: tone.glass ? 16 : 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      leadingIcon: leading,
      trailingIcon: selected
          ? Icon(Symbols.check, size: tone.glass ? 20 : 17)
          : trailing,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Inline suggestions and selection toolbars keep their existing dismissal
/// behavior; their appearance uses the same A3 entrance as anchored menus.
class MenuEntrance extends StatelessWidget {
  final Widget child;
  final Alignment alignment;
  const MenuEntrance({
    super.key,
    required this.child,
    this.alignment = Alignment.bottomLeft,
  });

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.pop.duration,
          curve: Motion.pop,
          child: child,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.scale(
              scale: .9 + .1 * t,
              alignment: alignment,
              child: child,
            ),
          ),
        );
}

class MenuSelect<T> extends StatelessWidget {
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T>? onChanged;
  final String? label;
  final Widget Function(T)? leading;
  const MenuSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = options.where((o) => o.$1 == value).firstOrNull;
    final enabled = onChanged != null && options.isNotEmpty;
    return LayoutBuilder(
      builder: (context, size) => ActionMenu<T>(
        tooltip: label ?? chosen?.$2 ?? '',
        width: size.maxWidth,
        enabled: enabled,
        onSelected: (value) => onChanged?.call(value),
        items: [
          for (final (option, words) in options)
            MenuAction(
              key: ValueKey('select-$option'),
              value: option,
              label: words,
              leading: leading?.call(option),
              selected: option == value,
            ),
        ],
        child: InputDecorator(
          isEmpty: chosen == null,
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            suffixIcon: const Icon(Symbols.keyboard_arrow_down, size: 20),
          ),
          child: Row(
            children: [
              if (chosen != null && leading != null) ...[
                leading!(chosen.$1),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  chosen?.$2 ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MenuPopover extends StatefulWidget {
  final Widget Function(BuildContext context, VoidCallback close) menuBuilder;
  final Widget Function(
    BuildContext context,
    VoidCallback toggle,
    FocusNode focus,
  )
  builder;
  final MenuController? controller;
  final double width;
  final bool alignEnd;
  const MenuPopover({
    super.key,
    required this.menuBuilder,
    required this.builder,
    this.controller,
    this.width = 280,
    this.alignEnd = false,
  });

  @override
  State<MenuPopover> createState() => _MenuPopoverState();
}

class _MenuPopoverState extends State<MenuPopover>
    with SingleTickerProviderStateMixin {
  late final menu = widget.controller ?? MenuController();
  final focus = FocusNode();
  final menuFocus = FocusScopeNode();
  LocalHistoryEntry? history;
  VoidCallback? hideOverlay;
  late final animation =
      AnimationController(
        vsync: this,
        duration: Motion.pop.duration,
        reverseDuration: Motion.popLeave,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          hideOverlay?.call();
          hideOverlay = null;
        }
        setState(() {});
      });
  late final eased = CurvedAnimation(
    parent: animation,
    curve: Motion.pop,
    reverseCurve: const FlippedCurve(Motion.leave),
  );

  @override
  void dispose() {
    final entry = history;
    history = null;
    entry?.remove();
    eased.dispose();
    animation.dispose();
    menuFocus.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final closing = animation.status == AnimationStatus.reverse;
    return RawMenuAnchor(
      controller: menu,
      childFocusNode: focus,
      consumeOutsideTaps: true,
      onOpen: () {
        history = LocalHistoryEntry(
          impliesAppBarDismissal: false,
          onRemove: () {
            if (history == null) return;
            history = null;
            menu.close();
          },
        );
        ModalRoute.of(context)!.addLocalHistoryEntry(history!);
      },
      onClose: () {
        final entry = history;
        history = null;
        entry?.remove();
      },
      onOpenRequested: (_, show) {
        hideOverlay = null;
        show();
        if (reduced) {
          animation.value = 1;
        } else {
          animation.forward();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && animation.isForwardOrCompleted) {
            menuFocus.requestFocus();
          }
        });
      },
      onCloseRequested: (hide) {
        if (reduced || animation.isDismissed) {
          animation.value = 0;
          hide();
        } else {
          hideOverlay = hide;
          animation.reverse();
        }
      },
      builder: (context, _, _) => widget.builder(context, () {
        if (animation.isForwardOrCompleted) {
          menu.close();
        } else {
          menu.open();
        }
      }, focus),
      overlayBuilder: (context, info) {
        final padding = MediaQuery.paddingOf(context);
        final bounds = Rect.fromLTRB(
          padding.left,
          padding.top,
          info.overlaySize.width - padding.right,
          info.overlaySize.height -
              math.max(padding.bottom, MediaQuery.viewInsetsOf(context).bottom),
        );
        final above = info.anchorRect.center.dy > bounds.center.dy;
        final alignment = Alignment(widget.alignEnd ? 1 : -1, above ? 1 : -1);
        return TapRegion(
          groupId: info.tapRegionGroupId,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // WebView2 forwards raw pointer events before Flutter's gesture
              // arena resolves. A real hit-test barrier prevents a dismissing
              // click from also pressing a button in the underlying page.
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (info.anchorRect.contains(event.localPosition) &&
                      animation.status == AnimationStatus.reverse) {
                    menu.open();
                  } else {
                    menu.close();
                  }
                },
              ),
              CustomSingleChildLayout(
                delegate: _MenuPosition(
                  info.anchorRect,
                  widget.width,
                  widget.alignEnd,
                  above,
                  bounds,
                ),
                child: ExcludeFocus(
                  excluding: closing,
                  child: ExcludeSemantics(
                    excluding: closing,
                    child: IgnorePointer(
                      ignoring: closing,
                      child: FocusScope(
                        node: menuFocus,
                        child: Shortcuts(
                          shortcuts: const {
                            SingleActivator(LogicalKeyboardKey.escape):
                                DismissIntent(),
                            SingleActivator(LogicalKeyboardKey.arrowDown):
                                NextFocusIntent(),
                            SingleActivator(LogicalKeyboardKey.arrowUp):
                                PreviousFocusIntent(),
                          },
                          child: AnimatedBuilder(
                            animation: animation,
                            child: MenuCard(
                              child: SingleChildScrollView(
                                child: widget.menuBuilder(context, menu.close),
                              ),
                            ),
                            builder: (context, child) {
                              final t = reduced ? 1.0 : eased.value;
                              return Opacity(
                                opacity: reduced
                                    ? 1
                                    : animation.status ==
                                          AnimationStatus.reverse
                                    ? animation.value
                                    : Motion.fade.transform(animation.value),
                                child: Transform.scale(
                                  scale: .9 + .1 * t,
                                  alignment: alignment,
                                  child: child,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  final Rect anchor, bounds;
  final double width;
  final bool alignEnd, above;
  _MenuPosition(
    this.anchor,
    this.width,
    this.alignEnd,
    this.above,
    this.bounds,
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: math.min(width, bounds.width - 24),
        maxWidth: math.min(width, bounds.width - 24),
        maxHeight: math.min(
          480,
          math.max(anchor.top - bounds.top, bounds.bottom - anchor.bottom) - 18,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final at = positionDependentBox(
      size: bounds.size,
      childSize: childSize,
      target: anchor.center - bounds.topLeft,
      verticalOffset: anchor.height / 2 + 6,
      preferBelow: !above,
      margin: 12,
    );
    return Offset(
      (alignEnd ? anchor.right - childSize.width : anchor.left).clamp(
        bounds.left + 12,
        bounds.right - childSize.width - 12,
      ),
      at.dy + bounds.top,
    );
  }

  @override
  bool shouldRelayout(_MenuPosition oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      alignEnd != oldDelegate.alignEnd ||
      above != oldDelegate.above ||
      bounds != oldDelegate.bounds;
}
