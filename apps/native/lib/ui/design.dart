import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/json.dart';
import '../data/account.dart';
import 'motion.dart';
import 'parts.dart';
import 'sheet.dart';
import 'shining_text.dart';
import 'connection_notice.dart';

export 'entry_motion.dart';
export 'menus.dart';
export 'motion.dart';
export 'parts.dart';
export 'shining_text.dart';
export 'sheet.dart';

final nativeRoutes = RouteObserver<ModalRoute<void>>();

const avatarShapes = [
  'dot',
  'bear',
  'bunny',
  'puppy',
  'mochi',
  'flower',
  'ghost',
  'antenna',
];
const avatarColors = [
  '#E8603C',
  '#FF3B47',
  '#FF4FA3',
  '#B05FD0',
  '#8B75AF',
  '#5B7CE6',
  '#2E8BFF',
  '#19B5C9',
  '#2F9E8F',
  '#22C55E',
  '#77A979',
  '#F2C230',
  '#D9932B',
  '#A9683A',
  '#8C8376',
  '#5A5A60',
];
Color hexColor(String value) =>
    Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));

const monoFont = 'JetBrains Mono';
const _sansFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Noto Sans SC',
];

/// Black and white on every device; the phone has larger controls. Bot avatars
/// are the only hue on screen, so a speaker can be told apart at a glance.
///
/// Surfaces are flat and parted by hairlines. Only what floats over the window
/// (menus, sheets, drawers, notices) casts a shadow.
@immutable
class Tone extends ThemeExtension<Tone> {
  final Color base, sidebar, surface, ink, ink2, ink3, line;
  final Color bubble, raised, hover, menu, danger;

  /// Behind list pages. The same as [base]: groups are parted by hairlines and
  /// space, not by a darker ground.
  final Color ground;

  /// The chosen part of a track: the page's own colour, edged by a hairline.
  final Color thumb;

  /// The navigation rail and the marker behind its chosen destination.
  final Color rail, railMark;

  /// The veil over the window behind a sheet.
  final Color dim;
  final bool glass;

  /// Control height, control corner and icon size. A desktop is pointer-driven
  /// and dense; a phone keeps Material's 40 dp controls inside 48 dp targets.
  final double control, corner, icon;

  /// Round icon buttons are smaller than text controls; a phone pads the target.
  final double button;
  final Color bar, fieldFocus;

  /// [rest] is empty: nothing resting on the page casts a shadow. [lift] is
  /// for what floats over the window.
  final List<BoxShadow> rest, lift;
  const Tone({
    required this.base,
    required this.sidebar,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.bubble,
    required this.raised,
    required this.hover,
    required this.menu,
    required this.danger,
    required this.rail,
    required this.dim,
    this.railMark = const Color(0x29ffffff),
    this.thumb = const Color(0xffffffff),
    this.ground = const Color(0xffffffff),
    this.glass = false,
    this.control = 32,
    this.corner = 8,
    this.icon = 20,
    this.button = 32,
    this.bar = Colors.transparent,
    this.fieldFocus = Colors.transparent,
    this.rest = const [],
    this.lift = const [],
  });

  /// Corners: 4 for small marks, 8 for controls and inner blocks, 12 for
  /// menus and sheets, 16 for bubbles, the composer and cards in the chat.
  static const r4 = 4.0, r8 = 8.0, r12 = 12.0, r16 = 16.0;

  /// A hairline.
  static const hair = .5;

  static const _liftLight = [
    BoxShadow(color: Color(0x1f000000), spreadRadius: .5),
    BoxShadow(color: Color(0x24000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
  static const _liftDark = [
    BoxShadow(color: Color(0xff383838), spreadRadius: .5),
    BoxShadow(color: Color(0xb3000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
  static const light = Tone(
    base: Color(0xffffffff),
    sidebar: Color(0xfff7f7f7),
    surface: Color(0xffffffff),
    ink: Color(0xff000000),
    ink2: Color(0xff555555),
    ink3: Color(0xff6e6e6e),
    line: Color(0xffdcdcdc),
    bubble: Color(0xfff2f2f2),
    raised: Color(0xffe9e9e9),
    hover: Color(0xfff2f2f2),
    menu: Color(0xffffffff),
    danger: Color(0xffc22f2f),
    rail: Color(0xff000000),
    dim: Color(0x47000000),
    lift: _liftLight,
  );
  static const dark = Tone(
    base: Color(0xff000000),
    sidebar: Color(0xff0c0c0c),
    surface: Color(0xff000000),
    ink: Color(0xffffffff),
    ink2: Color(0xffb4b4b4),
    ink3: Color(0xff8e8e8e),
    line: Color(0xff2c2c2c),
    bubble: Color(0xff1c1c1c),
    raised: Color(0xff262626),
    hover: Color(0xff1a1a1a),
    menu: Color(0xff000000),
    danger: Color(0xffff8a80),
    rail: Color(0xff141414),
    railMark: Color(0x24ffffff),
    dim: Color(0x9e000000),
    thumb: Color(0xff000000),
    ground: Color(0xff000000),
    lift: _liftDark,
  );
  // The phone keeps the same flat black and white with larger controls.
  static const glassLight = Tone(
    glass: true,
    control: 44,
    corner: 12,
    icon: 24,
    button: 40,
    base: Color(0xffffffff),
    sidebar: Colors.transparent,
    surface: Color(0xffffffff),
    ink: Color(0xff000000),
    ink2: Color(0xff555555),
    ink3: Color(0xff6e6e6e),
    line: Color(0xffdcdcdc),
    bubble: Color(0xfff2f2f2),
    raised: Color(0xffe9e9e9),
    hover: Color(0xfff2f2f2),
    menu: Color(0xffffffff),
    danger: Color(0xffc22f2f),
    rail: Color(0xff000000),
    dim: Color(0x47000000),
    bar: Color(0xffffffff),
    fieldFocus: Color(0xffffffff),
    lift: _liftLight,
  );
  static const glassDark = Tone(
    glass: true,
    control: 44,
    corner: 12,
    icon: 24,
    button: 40,
    base: Color(0xff000000),
    sidebar: Colors.transparent,
    surface: Color(0xff000000),
    ink: Color(0xffffffff),
    ink2: Color(0xffb4b4b4),
    ink3: Color(0xff8e8e8e),
    line: Color(0xff2c2c2c),
    bubble: Color(0xff1c1c1c),
    raised: Color(0xff262626),
    hover: Color(0xff1a1a1a),
    menu: Color(0xff000000),
    danger: Color(0xffff8a80),
    rail: Color(0xff141414),
    railMark: Color(0x24ffffff),
    dim: Color(0x9e000000),
    thumb: Color(0xff000000),
    ground: Color(0xff000000),
    bar: Color(0xff000000),
    fieldFocus: Color(0xff000000),
    lift: _liftDark,
  );
  @override
  Tone copyWith() => this;
  @override
  Tone lerp(Tone? other, double t) => other == null || t < .5 ? this : other;
}

extension ToneOf on BuildContext {
  Tone get tone => Theme.of(this).extension<Tone>()!;
}

class _PageTransitions extends PageTransitionsBuilder {
  const _PageTransitions();
  @override
  Duration get transitionDuration => Motion.push.duration;
  @override
  Duration get reverseTransitionDuration => Motion.pushLeave;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.still(context)) return child;
    if (!context.tone.glass) {
      // A desktop page takes the place of what was there: it rises a little
      // and settles.
      return FadeTransition(
        opacity: Motion.fadeIn(animation),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .02),
            end: Offset.zero,
          ).animate(Motion.spring(animation, Motion.swap)),
          child: child,
        ),
      );
    }
    // A phone page slides over the last one, which steps back and dims.
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-.22, 0),
      ).animate(Motion.spring(secondaryAnimation, Motion.push)),
      child: FadeTransition(
        opacity: Tween<double>(
          begin: 1,
          end: .6,
        ).animate(Motion.fadeIn(secondaryAnimation)),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(Motion.spring(animation, Motion.push)),
          child: ColoredBox(color: context.tone.base, child: child),
        ),
      ),
    );
  }
}

ThemeData appTheme(Brightness brightness, {bool? glass}) {
  final dark = brightness == Brightness.dark;
  final frosted = glass ?? Platform.isAndroid;
  final tone = frosted
      ? (dark ? Tone.glassDark : Tone.glassLight)
      : (dark ? Tone.dark : Tone.light);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: tone.ink,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      ).copyWith(
        primary: tone.ink,
        onPrimary: tone.base,
        secondary: tone.ink,
        onSecondary: tone.base,
        surface: tone.menu,
        onSurface: tone.ink,
        onSurfaceVariant: tone.ink2,
        surfaceTint: Colors.transparent,
        outline: tone.ink3,
        outlineVariant: tone.line,
        error: tone.danger,
      );
  // Four sizes: 12 for marks and labels, 14 and 16 for reading and controls,
  // 22 for the few large titles. A desktop reads at 14, a phone at 16. White
  // text on black looks heavier than black on white, so dark steps one weight
  // down.
  final strong = dark ? FontWeight.w600 : FontWeight.w700;
  final medium = dark ? FontWeight.w500 : FontWeight.w600;
  final read = frosted ? 16.0 : 14.0;
  final text =
      (dark ? Typography.whiteMountainView : Typography.blackMountainView)
          .copyWith(
            headlineMedium: TextStyle(
              fontSize: 22,
              fontWeight: strong,
              height: 28 / 22,
              color: tone.ink,
            ),
            headlineSmall: TextStyle(
              fontSize: 22,
              fontWeight: strong,
              height: 28 / 22,
              color: tone.ink,
            ),
            titleLarge: TextStyle(
              fontSize: 16,
              fontWeight: strong,
              height: 22 / 16,
              color: tone.ink,
            ),
            titleMedium: TextStyle(
              fontSize: read,
              fontWeight: medium,
              height: frosted ? 22 / 16 : 20 / 14,
              color: tone.ink,
            ),
            titleSmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 16 / 12,
              color: tone.ink3,
            ),
            bodyLarge: TextStyle(
              fontSize: read,
              height: frosted ? 24 / 16 : 22 / 14,
              color: tone.ink,
            ),
            bodyMedium: TextStyle(
              fontSize: read,
              height: frosted ? 24 / 16 : 22 / 14,
              color: tone.ink,
            ),
            bodySmall: TextStyle(
              fontSize: frosted ? 14 : 12,
              height: frosted ? 20 / 14 : 16 / 12,
              color: tone.ink2,
            ),
            labelLarge: TextStyle(fontSize: read, fontWeight: medium),
            // Statuses and counts change while you watch: steady-width
            // digits keep them from shaking, and nothing is under 12.
            labelMedium: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: tone.ink3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            labelSmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: tone.ink3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
          .apply(fontFamily: 'Nunito', fontFamilyFallback: _sansFallback);
  InputBorder field(Color color) => ShapedInputBorder(
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(tone.corner),
    ),
    borderSide: BorderSide(color: color, width: Tone.hair),
  );
  // Buttons and fields share one corner; a phone's is larger, as its controls
  // are. Icon buttons are rounded squares under a pointer and circles under
  // a thumb.
  final control = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(tone.corner),
  );
  final buttonSize = Size(0, tone.control);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: frosted ? VisualDensity.standard : VisualDensity.compact,
    materialTapTargetSize: frosted
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
    colorScheme: scheme,
    fontFamily: 'Nunito',
    fontFamilyFallback: _sansFallback,
    textTheme: text,
    extensions: [tone],
    scaffoldBackgroundColor: frosted ? Colors.transparent : tone.base,
    canvasColor: frosted ? tone.menu : tone.base,
    splashFactory: NoSplash.splashFactory,
    highlightColor: tone.hover,
    hoverColor: tone.hover,
    focusColor: tone.hover,
    dividerColor: tone.line,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _PageTransitions(),
        TargetPlatform.windows: _PageTransitions(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: tone.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: frosted ? 52 : 44,
      titleSpacing: 4,
      iconTheme: IconThemeData(color: tone.ink, size: tone.icon),
      actionsIconTheme: IconThemeData(color: tone.ink, size: tone.icon),
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    iconTheme: IconThemeData(color: tone.ink, size: tone.icon),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tone.ink,
        disabledForegroundColor: tone.ink3,
        hoverColor: tone.hover,
        highlightColor: tone.hover,
        visualDensity: VisualDensity.standard,
        minimumSize: Size.square(tone.button),
        padding: EdgeInsets.zero,
        iconSize: tone.icon - 1,
        shape: frosted
            ? const CircleBorder()
            : const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(Tone.r8)),
              ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tone.surface,
      hoverColor: Colors.transparent,
      labelStyle: TextStyle(color: tone.ink2),
      floatingLabelStyle: TextStyle(color: tone.ink2),
      hintStyle: TextStyle(color: tone.ink3),
      prefixIconColor: tone.ink3,
      suffixIconColor: tone.ink3,
      border: field(tone.line),
      enabledBorder: field(tone.line),
      disabledBorder: field(tone.line),
      focusedBorder: field(tone.ink),
      errorBorder: field(tone.danger),
      focusedErrorBorder: field(tone.danger),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: frosted ? 14 : 10,
        vertical: frosted ? 12 : 7,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tone.ink,
      selectionColor: tone.ink.withValues(alpha: .18),
      selectionHandleColor: tone.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tone.ink,
        foregroundColor: tone.base,
        disabledBackgroundColor: tone.raised,
        disabledForegroundColor: tone.ink3,
        visualDensity: VisualDensity.standard,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: text.labelLarge,
        shape: control,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tone.ink,
        disabledForegroundColor: tone.ink3,
        side: BorderSide(color: tone.line, width: Tone.hair),
        visualDensity: VisualDensity.standard,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: text.labelLarge,
        shape: control,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tone.ink2,
        disabledForegroundColor: tone.ink3,
        visualDensity: VisualDensity.standard,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: text.labelLarge,
        shape: control,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tone.ink2,
      textColor: tone.ink,
      selectedColor: tone.ink,
      selectedTileColor: tone.raised,
      subtitleTextStyle: text.bodySmall,
      titleTextStyle: text.bodyMedium,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: frosted ? 8 : 6,
      minTileHeight: frosted ? 52 : 40,
      minLeadingWidth: 0,
      horizontalTitleGap: 10,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: tone.ink3, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tone.ink
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(tone.base),
    ),
    chipTheme: ChipThemeData(
      shape: control,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide(color: tone.line, width: .5),
      backgroundColor: Colors.transparent,
      selectedColor: tone.ink,
      showCheckmark: false,
      labelStyle: text.labelLarge?.copyWith(
        color: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? tone.base : tone.ink2,
        ),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: tone.ink3,
      collapsedIconColor: tone.ink3,
      textColor: tone.ink,
      collapsedTextColor: tone.ink,
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: tone.ink, width: 1.5),
      ),
      labelColor: tone.ink,
      unselectedLabelColor: tone.ink3,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w400,
      ),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // Every menu: a white card, a hairline, a soft shadow and round corners.
    popupMenuTheme: PopupMenuThemeData(
      color: tone.menu,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: dark ? .7 : .14),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(Tone.r12),
        side: BorderSide(
          color: dark ? const Color(0xff383838) : const Color(0x1f000000),
          width: Tone.hair,
        ),
      ),
      menuPadding: const EdgeInsets.all(6),
      textStyle: text.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tone.menu),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(Tone.r12),
          ),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tone.menu,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(
        color: tone.ink,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      textStyle: text.labelMedium?.copyWith(color: tone.base),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tone.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: tone.base),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(Tone.r12),
      ),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tone.menu,
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(Tone.r12),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tone.ink,
      linearTrackColor: tone.raised,
      circularTrackColor: Colors.transparent,
      strokeWidth: 2,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(4),
      radius: const Radius.circular(4),
      thumbColor: WidgetStatePropertyAll(tone.raised),
    ),
    dividerTheme: DividerThemeData(
      color: tone.line,
      thickness: Tone.hair,
      space: Tone.hair,
    ),
  );
}

MarkdownStyleSheet markdownStyle(BuildContext context, {Color? color}) {
  final tone = context.tone;
  final ink = color ?? tone.ink;
  final body = Theme.of(context).textTheme.bodyMedium!.copyWith(color: ink);
  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(decoration: TextDecoration.underline),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    h1: body.copyWith(
      fontSize: body.fontSize! + 4,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    h2: body.copyWith(
      fontSize: body.fontSize! + 2,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    h3: body.copyWith(fontWeight: FontWeight.w700, height: 1.3),
    h4: body.copyWith(fontWeight: FontWeight.w700),
    h5: body.copyWith(fontWeight: FontWeight.w700),
    h6: body.copyWith(fontWeight: FontWeight.w700),
    listBullet: body,
    blockSpacing: 10,
    code: body.copyWith(
      fontFamily: monoFont,
      fontSize: 13,
      // Text-span backgrounds paint over the selection, so keep this tint translucent.
      backgroundColor: ink.withValues(alpha: .08),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: ShapeDecoration(
      color: ink.withValues(alpha: .06),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(8)),
    ),
    blockquote: body.copyWith(color: tone.ink2),
    blockquotePadding: const EdgeInsets.only(left: 14),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: tone.line, width: 2)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: tone.line)),
    ),
    tableBorder: TableBorder.all(color: tone.line),
    tableColumnWidth: const FixedColumnWidth(180),
    tableScrollbarThumbVisibility: true,
    tableHead: body.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
  );
}

/// A round bot face. A null color draws the brand mark in the current ink.
/// While working its ears move and its eyes scan; idle, it blinks now and then.
class CatAvatar extends StatefulWidget {
  final String? color;
  final String shape;
  final double size;
  final bool working, twitch;
  const CatAvatar({
    super.key,
    this.color,
    this.shape = 'dot',
    this.size = 32,
    this.working = false,
    this.twitch = false,
  });
  CatAvatar.of(
    Json bot, {
    super.key,
    this.size = 32,
    this.working = false,
    this.twitch = false,
  }) : color = '${bot['avatar']['color']}',
       shape = '${bot['avatar']['shape']}';
  @override
  State<CatAvatar> createState() => _CatAvatarState();
}

class _CatAvatarState extends State<CatAvatar> with TickerProviderStateMixin {
  static final _random = math.Random();
  late final motion = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_catLoop * 1000).round()),
  );
  late final blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final twitch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  Timer? nextBlink;

  void sync() {
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.working && !still) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
      motion.value = 0;
    }
    nextBlink?.cancel();
    nextBlink = null;
    if (!widget.working && !still) scheduleBlink();
  }

  void scheduleBlink() {
    nextBlink = Timer(
      Duration(milliseconds: 4000 + _random.nextInt(3000)),
      () async {
        if (!mounted) return;
        await blink.forward(from: 0);
        if (!mounted) return;
        blink.value = 0;
        if (nextBlink != null) scheduleBlink();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(CatAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.working != widget.working) sync();
    if (widget.twitch &&
        !oldWidget.twitch &&
        !widget.working &&
        !MediaQuery.disableAnimationsOf(context)) {
      twitch.forward(from: 0);
    }
  }

  @override
  void dispose() {
    nextBlink?.cancel();
    motion.dispose();
    blink.dispose();
    twitch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final color = widget.color;
    final body = color == null ? tone.ink : hexColor(color);
    return Semantics(
      label: 'Bot',
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _CatPainter(
            shape: widget.shape,
            motion: motion,
            blink: blink,
            twitch: twitch,
            body: body,
            eyes: color == null
                ? tone.base
                : body.computeLuminance() > .45
                ? const Color(0xff141414)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// One loop of the working motion, in seconds: whole cycles of ears and eyes.
const _catLoop = 9.6;

class _CatPainter extends CustomPainter {
  final String shape;
  final Animation<double> motion, blink, twitch;
  final Color body, eyes;
  _CatPainter({
    required this.shape,
    required this.motion,
    required this.blink,
    required this.twitch,
    required this.body,
    required this.eyes,
  }) : super(repaint: Listenable.merge([motion, blink, twitch]));

  /// 0 to 1 and back over [period] seconds, starting at 0.
  double wave(double period) {
    final seconds = motion.value * _catLoop;
    return (1 - math.cos(2 * math.pi * seconds / period)) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40);
    final fill = Paint()..color = body;
    // Working ears lean in by 8 degrees; a hover flicks them out by 12.
    final flick = twitch.value < .4
        ? twitch.value / .4
        : (1 - twitch.value) / .6;
    final lean = (wave(1.2) * 8 - flick * 12) * math.pi / 180;

    void pair(Offset pivot, void Function() draw) {
      for (final mirrored in [false, true]) {
        canvas.save();
        if (mirrored) {
          canvas.translate(40, 0);
          canvas.scale(-1, 1);
        }
        canvas.translate(pivot.dx, pivot.dy);
        canvas.rotate(lean);
        canvas.translate(-pivot.dx, -pivot.dy);
        draw();
        canvas.restore();
      }
    }

    void soft(List<Offset> points, double round) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = body
          ..style = PaintingStyle.stroke
          ..strokeWidth = round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void tilted(Offset center, double width, double height, double degrees) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        fill,
      );
      canvas.restore();
    }

    var eyeY = 23.5, eyeGap = 5.5;
    switch (shape) {
      case 'bear':
        pair(const Offset(13, 15), () {
          canvas.drawCircle(const Offset(9.5, 11.5), 5.8, fill);
        });
        canvas.drawCircle(const Offset(20, 23), 15, fill);
      case 'bunny':
        pair(const Offset(14.5, 17), () {
          tilted(const Offset(13, 9), 7.6, 17, -8);
        });
        canvas.drawCircle(const Offset(20, 25.5), 13.5, fill);
        eyeY = 26;
        eyeGap = 5;
      case 'puppy':
        pair(const Offset(9, 13), () {
          tilted(const Offset(6.6, 22), 8.4, 18, 10);
        });
        canvas.drawCircle(const Offset(20, 21.5), 14.5, fill);
        eyeY = 22;
        eyeGap = 5.2;
      case 'mochi':
        pair(const Offset(14, 13), () {
          soft(const [Offset(8.5, 13), Offset(10, 7), Offset(15.5, 11)], 2.6);
        });
        canvas.drawRRect(
          RRect.fromLTRBR(3, 11, 37, 38, const Radius.circular(13.5)),
          fill,
        );
        eyeY = 24;
        eyeGap = 7;
      case 'flower':
        final spin = motion.value * 2 * math.pi + flick * .3;
        for (var petal = 0; petal < 6; petal++) {
          final angle = spin + petal * math.pi / 3;
          canvas.drawCircle(
            Offset(20 + 10.2 * math.cos(angle), 20 + 10.2 * math.sin(angle)),
            7.2,
            fill,
          );
        }
        canvas.drawCircle(const Offset(20, 20), 11, fill);
        eyeY = 20;
        eyeGap = 4.4;
      case 'ghost':
        canvas.translate(0, -math.sin(wave(1.2) * math.pi) * 1.2 - flick);
        final path = Path()
          ..moveTo(6, 20)
          ..arcToPoint(const Offset(34, 20), radius: const Radius.circular(14))
          ..lineTo(34, 35);
        for (var hop = 0; hop < 6; hop++) {
          final from = 34 - hop * 28 / 6;
          path.quadraticBezierTo(
            from - 28 / 12,
            hop.isEven ? 39 : 31,
            from - 28 / 6,
            35,
          );
        }
        path.close();
        canvas.drawPath(path, fill);
        eyeY = 19.5;
        eyeGap = 5;
      case 'antenna':
        pair(const Offset(15, 12), () {
          canvas.drawLine(
            const Offset(15, 11),
            const Offset(11.5, 4.5),
            Paint()
              ..color = body
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(const Offset(11, 3.8), 2.8, fill);
        });
        canvas.drawRRect(
          RRect.fromLTRBR(5.5, 9.5, 34.5, 37.5, const Radius.circular(11)),
          fill,
        );
        eyeGap = 5.6;
      default:
        pair(const Offset(15, 16), () {
          soft(const [Offset(7.6, 16), Offset(9.6, 6.4), Offset(15.4, 11)], 3);
        });
        canvas.drawCircle(const Offset(20, 23), 15, fill);
    }

    canvas.save();
    canvas.translate((wave(3.2) - .5) * 3, eyeY);
    canvas.scale(1, 1 - .9 * math.sin(blink.value * math.pi));
    final eye = Paint()..color = eyes;
    canvas.drawCircle(Offset(20 - eyeGap, 0), 2.2, eye);
    canvas.drawCircle(Offset(20 + eyeGap, 0), 2.2, eye);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatPainter old) =>
      old.body != body || old.eyes != eyes || old.shape != shape;
}

/// Group avatar: its first two members leaning together.
class GroupAvatar extends StatelessWidget {
  final List<Json> avatars;
  final double size;
  final bool working;
  const GroupAvatar({
    super.key,
    required this.avatars,
    this.size = 32,
    this.working = false,
  });
  @override
  Widget build(BuildContext context) {
    final small = size * .68;
    return Semantics(
      label: 'Group',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            for (final (index, avatar) in avatars.take(2).indexed)
              Positioned(
                left: index == 0 ? 0 : size - small,
                top: index == 0 ? 0 : size - small,
                child: CatAvatar(
                  color: '${avatar['color']}',
                  shape: '${avatar['shape']}',
                  size: small,
                  working: working,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ErrorNotice extends StatelessWidget {
  final String text;

  /// What to do about it, such as trying again.
  final Widget? action;
  const ErrorNotice(this.text, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final tone = context.tone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: StatusDot(color: tone.danger),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tone.danger),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// The next step: a new page, or, inside a floating sheet, the sheet's next
/// step in the same frame.
Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(
      InSheet.of(context)
          ? SheetRoute<T>(page, first: false)
          : MaterialPageRoute(builder: (_) => page),
    );

class AsyncPane extends StatefulWidget {
  final Json? initialData;
  final Future<Json> Function() load;
  final Widget Function(BuildContext, Json, VoidCallback) builder;
  const AsyncPane({
    super.key,
    required this.load,
    required this.builder,
    this.initialData,
  });
  @override
  State<AsyncPane> createState() => _AsyncPaneState();
}

class _AsyncPaneState extends State<AsyncPane> {
  late Json? confirmed = widget.initialData;
  int? revision;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ContentRefreshScope.of(context);
    if (revision != null && revision != current) value = widget.load();
    revision = current;
  }

  late Future<Json> value = widget.load();
  void reload() => setState(() {
    value = widget.load();
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: value,
    builder: (context, snapshot) {
      if (snapshot.hasData) confirmed = snapshot.data;
      if (confirmed != null &&
          (!snapshot.hasError || isTransientConnectionError(snapshot.error!))) {
        return widget.builder(context, confirmed!, reload);
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorNotice('${snapshot.error}'),
                IconButton(
                  tooltip: '重试 / Retry',
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) return const Center(child: ShiningText());
      return widget.builder(context, snapshot.data!, reload);
    },
  );
}
