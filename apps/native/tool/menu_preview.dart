import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nekodot_native/ui/design.dart';

// An isolated, native design review. No account, Node, preferences or API calls.
// A1/A2/A3 are motion review identifiers, not product settings or new copy.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'nekodot A1 / A2 / A3',
        size: Size(1280, 920),
        minimumSize: Size(920, 700),
      ),
    );
    await windowManager.show();
  }
  runApp(const MenuPreviewApp());
}

const _models = ['gpt-6.1-sol', 'gpt-6-astra', 'gpt-6-sol', 'gpt-6-luna'];

class _Variant {
  final String id;
  final int enterMs, exitMs;
  final Curve curve;
  const _Variant(this.id, this.enterMs, this.exitMs, this.curve);

  // Appearance A is fixed; only motion differs between columns.
  double get radius => 16;
  double get inset => 6;
  double get rowHeight => 36;
  double get elevation => 6;
  Duration get enter => Duration(milliseconds: enterMs);
  Duration get exit => Duration(milliseconds: exitMs);
}

const _variants = [
  _Variant('A1', 160, 120, Curves.easeOutCubic),
  _Variant('A2', 220, 160, Curves.easeOutQuint),
  _Variant('A3', 300, 180, Curves.easeOutBack),
];

class MenuPreviewApp extends StatefulWidget {
  const MenuPreviewApp({super.key});

  @override
  State<MenuPreviewApp> createState() => _MenuPreviewAppState();
}

class _MenuPreviewAppState extends State<MenuPreviewApp> {
  bool dark = false, mobile = false, english = false;
  final menus = List.generate(3, (_) => MenuController());
  bool replaying = false;

  Future<void> replay() async {
    setState(() => replaying = true);
    for (final menu in menus) {
      menu.close();
    }
    // A single preview cycle, not a product interaction delay or idle loop.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    if (!mobile) {
      for (final menu in menus) {
        menu.open();
      }
    }
    setState(() => replaying = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(dark ? Brightness.dark : Brightness.light),
    builder: (_, child) => RepaintBoundary(
      key: const ValueKey('menu-preview-canvas'),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.tone.ground,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
                child: Row(
                  children: [
                    const _ReviewAvatar(size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'nekodot',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (!mobile) ...[
                      IconButton(
                        key: const ValueKey('menu-preview-play'),
                        tooltip: 'A1 / A2 / A3',
                        onPressed: replaying ? null : replay,
                        icon: const Icon(Icons.replay_rounded),
                      ),
                      const SizedBox(width: 12),
                    ],
                    IconButton(
                      key: const ValueKey('menu-preview-device'),
                      tooltip: mobile ? 'Windows' : 'Android',
                      onPressed: () => setState(() => mobile = !mobile),
                      icon: Icon(
                        mobile
                            ? Icons.desktop_windows_outlined
                            : Icons.smartphone_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      key: const ValueKey('menu-preview-theme'),
                      tooltip: dark ? '浅色' : '深色',
                      onPressed: () => setState(() => dark = !dark),
                      icon: Icon(
                        dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('menu-preview-language'),
                      onPressed: () => setState(() => english = !english),
                      child: Text(english ? 'EN' : '中'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1136),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _variants.length; i++) ...[
                            if (i > 0) const SizedBox(width: 40),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Text(
                                      _variants[i].id,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        color: context.tone.ink2,
                                      ),
                                    ),
                                  ),
                                  if (mobile)
                                    _PhoneReview(
                                      key: ValueKey(
                                        'phone-${_variants[i].id}-$dark-$english',
                                      ),
                                      variant: _variants[i],
                                      dark: dark,
                                      english: english,
                                    )
                                  else
                                    _DesktopReview(
                                      variant: _variants[i],
                                      english: english,
                                      controller: menus[i],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DesktopReview extends StatefulWidget {
  final _Variant variant;
  final bool english;
  final MenuController controller;
  const _DesktopReview({
    required this.variant,
    required this.english,
    required this.controller,
  });

  @override
  State<_DesktopReview> createState() => _DesktopReviewState();
}

class _DesktopReviewState extends State<_DesktopReview> {
  String model = _models.first;
  int bot = 0;
  String tr(String zh, String en) => widget.english ? en : zh;

  @override
  Widget build(BuildContext context) {
    final variant = widget.variant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(tr('模型', 'Model')),
        _SelectAnchor(
          key: ValueKey('model-anchor-${variant.id}'),
          variant: variant,
          value: model,
          controller: widget.controller,
          onSelected: (value) => setState(() => model = value),
        ),
        const SizedBox(height: 176),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: _SectionTitle(tr('空间', 'Space'))),
            _AnimatedAnchor(
              variant: variant,
              width: 248,
              alignRight: true,
              menu: _SpaceActions(
                variant: variant,
                english: widget.english,
                autofocus: true,
              ),
              builder: (toggle, focus) => IconButton(
                key: ValueKey('actions-anchor-${variant.id}'),
                tooltip: tr('更多', 'More'),
                focusNode: focus,
                onPressed: toggle,
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 176),
        const SizedBox(height: 28),
        const _SectionTitle('Dot'),
        _MenuSurface(
          variant: variant,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                _Option(
                  key: ValueKey('bot-${variant.id}-$i'),
                  variant: variant,
                  label: 'Dot ${String.fromCharCode(65 + i)}',
                  leading: _ReviewAvatar(
                    size: 22,
                    color: ['#558B61', '#E8603C', '#5B7CE6'][i],
                    shape: ['dot', 'bunny', 'bear'][i],
                  ),
                  selected: bot == i,
                  onPressed: () => setState(() => bot = i),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, color: context.tone.ink2),
    ),
  );
}

class _MenuSurface extends StatelessWidget {
  final _Variant variant;
  final Widget child;
  const _MenuSurface({required this.variant, required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: context.tone.menu,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black.withValues(alpha: .16),
    elevation: variant.elevation,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(variant.radius),
      side: BorderSide(color: context.tone.line, width: .5),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: EdgeInsets.all(variant.inset), child: child),
  );
}

class _Option extends StatelessWidget {
  final _Variant variant;
  final String label;
  final Widget? leading;
  final bool selected, mobile, autofocus;
  final VoidCallback? onPressed;
  const _Option({
    super.key,
    required this.variant,
    required this.label,
    this.leading,
    this.selected = false,
    this.mobile = false,
    this.autofocus = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final ink = tone.ink;
    return MenuItemButton(
      overflowAxis: Axis.vertical,
      autofocus: autofocus,
      onPressed: onPressed == null
          ? null
          : () {
              MenuController.maybeOf(context)?.close();
              onPressed!();
            },
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(double.infinity, mobile ? 48 : variant.rowHeight),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(variant.radius - variant.inset),
          ),
        ),
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return tone.hover;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return tone.hover;
          }
          return Colors.transparent;
        }),
        overlayColor: WidgetStatePropertyAll(ink.withValues(alpha: .05)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? tone.ink3 : ink,
        ),
        iconColor: WidgetStatePropertyAll(ink),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: mobile ? 16 : 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      leadingIcon: leading,
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: mobile ? 20 : 17)
          : null,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _SelectAnchor extends StatelessWidget {
  final _Variant variant;
  final String value;
  final ValueChanged<String> onSelected;
  final MenuController controller;
  const _SelectAnchor({
    super.key,
    required this.variant,
    required this.value,
    required this.onSelected,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => _AnimatedAnchor(
      variant: variant,
      controller: controller,
      width: size.maxWidth,
      menu: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final model in _models)
            _Option(
              key: ValueKey('popup-model-${variant.id}-$model'),
              variant: variant,
              label: model,
              selected: model == value,
              autofocus: model == value,
              onPressed: () => onSelected(model),
            ),
        ],
      ),
      builder: (toggle, focus) => OutlinedButton(
        key: ValueKey('open-model-${variant.id}'),
        focusNode: focus,
        onPressed: toggle,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(double.infinity, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: context.tone.line, width: .5),
          backgroundColor: context.tone.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(variant.radius - variant.inset),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _SpaceActions extends StatelessWidget {
  final _Variant variant;
  final bool english, autofocus;
  const _SpaceActions({
    required this.variant,
    required this.english,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (icon, zh, en) in [
        (Icons.edit_outlined, '请 Dot 修改', 'Edit with Dot'),
        (Icons.drive_file_rename_outline, '重命名', 'Rename'),
        (Icons.language_outlined, '网站访问', 'Website access'),
        (Icons.archive_outlined, '归档', 'Archive'),
      ]) ...[
        if (icon == Icons.archive_outlined)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Divider(height: 1, thickness: .5, color: context.tone.line),
          ),
        _Option(
          variant: variant,
          label: english ? en : zh,
          leading: Icon(icon, size: 17),
          autofocus: autofocus && icon == Icons.edit_outlined,
          onPressed: () {},
        ),
      ],
    ],
  );
}

// RawMenuAnchor exposes Flutter's official open/close animation hooks. This
// preview changes the transition, not the native overlay or menu controller.
class _AnimatedAnchor extends StatefulWidget {
  final _Variant variant;
  final MenuController? controller;
  final double width;
  final bool alignRight;
  final Widget menu;
  final Widget Function(VoidCallback toggle, FocusNode focus) builder;
  const _AnimatedAnchor({
    required this.variant,
    required this.width,
    required this.menu,
    required this.builder,
    this.controller,
    this.alignRight = false,
  });

  @override
  State<_AnimatedAnchor> createState() => _AnimatedAnchorState();
}

class _AnimatedAnchorState extends State<_AnimatedAnchor>
    with SingleTickerProviderStateMixin {
  late final menu = widget.controller ?? MenuController();
  final focus = FocusNode();
  final menuFocus = FocusScopeNode();
  late final animation =
      AnimationController(
        vsync: this,
        duration: widget.variant.enter,
        reverseDuration: widget.variant.exit,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          hideOverlay?.call();
          hideOverlay = null;
        }
        setState(() {});
      });
  late final eased = CurvedAnimation(
    parent: animation,
    curve: widget.variant.curve,
    reverseCurve: Curves.easeInCubic,
  );
  VoidCallback? hideOverlay;

  @override
  void dispose() {
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
      builder: (_, _, _) => widget.builder(
        () => animation.isForwardOrCompleted ? menu.close() : menu.open(),
        focus,
      ),
      overlayBuilder: (context, info) => Positioned(
        top: info.anchorRect.bottom + 6,
        left: widget.alignRight
            ? info.anchorRect.right - widget.width
            : info.anchorRect.left,
        width: widget.width,
        child: TapRegion(
          groupId: info.tapRegionGroupId,
          onTapOutside: (_) => menu.close(),
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
                      child: _MenuSurface(
                        variant: widget.variant,
                        child: widget.menu,
                      ),
                      builder: (context, child) {
                        final t = reduced ? 1.0 : eased.value;
                        final alignment = widget.alignRight
                            ? Alignment.topRight
                            : Alignment.topLeft;
                        final transformed = switch (widget.variant.id) {
                          'A1' => Transform.translate(
                            offset: Offset(0, -6 * (1 - t)),
                            child: child,
                          ),
                          'A2' => Transform.scale(
                            scale: .92 + .08 * t,
                            alignment: alignment,
                            child: child,
                          ),
                          _ => Transform.scale(
                            scaleX: .97 + .03 * t,
                            scaleY: .84 + .16 * t,
                            alignment: alignment,
                            child: child,
                          ),
                        };
                        return Opacity(
                          key: ValueKey(
                            'motion-${widget.variant.id}-${widget.alignRight ? 'actions' : 'model'}',
                          ),
                          opacity: reduced
                              ? 1
                              : Curves.easeOut.transform(animation.value),
                          child: transformed,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneReview extends StatelessWidget {
  final _Variant variant;
  final bool dark, english;
  const _PhoneReview({
    super.key,
    required this.variant,
    required this.dark,
    required this.english,
  });

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: 390,
      height: 760,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(32),
        child: Theme(
          data: appTheme(
            dark ? Brightness.dark : Brightness.light,
            glass: true,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: const Size(390, 760),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => _PhoneScene(variant: variant, english: english),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PhoneScene extends StatefulWidget {
  final _Variant variant;
  final bool english;
  const _PhoneScene({required this.variant, required this.english});

  @override
  State<_PhoneScene> createState() => _PhoneSceneState();
}

class _PhoneSceneState extends State<_PhoneScene> {
  String value = _models.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) choose();
    });
  }

  Future<void> choose() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: widget.variant.enter,
              reverseDuration: widget.variant.exit,
              // Keep the native sheet attached to the bottom edge, even for A3.
              curve: switch (widget.variant.id) {
                'A1' => Curves.easeOutCubic,
                'A2' => Curves.easeInOutCubicEmphasized,
                _ => Curves.easeOutQuint,
              },
              reverseCurve: Curves.easeInCubic,
            ),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(widget.variant.radius + 12),
        ),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.variant.inset + 8,
            0,
            widget.variant.inset + 8,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                child: Text(
                  widget.english ? 'Model' : '模型',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final model in _models)
                _Option(
                  key: ValueKey('phone-option-${widget.variant.id}-$model'),
                  variant: widget.variant,
                  label: model,
                  selected: model == value,
                  mobile: true,
                  onPressed: () => Navigator.pop(sheet, model),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && result != null) setState(() => value = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.tone.base,
    appBar: AppBar(title: Text(widget.english ? 'Settings' : '设置')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(child: _ReviewAvatar(size: 44, color: '#558B61')),
          const SizedBox(height: 20),
          _SectionTitle(widget.english ? 'Model' : '模型'),
          OutlinedButton(
            key: ValueKey('phone-model-${widget.variant.id}'),
            onPressed: choose,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(color: context.tone.line, width: .5),
            ),
            child: Row(
              children: [
                Expanded(child: Text(value)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Static reference avatars keep this comparison about menus, not idle blinking.
class _ReviewAvatar extends StatelessWidget {
  final double size;
  final String? color;
  final String shape;
  const _ReviewAvatar({required this.size, this.color, this.shape = 'dot'});

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: CatAvatar(size: size, color: color, shape: shape),
  );
}
