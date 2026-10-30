import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/client.dart';
import 'parts.dart';

export 'parts.dart';

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

/// Black and white: flat on the desktop, frosted glass on the phone. Bot avatars
/// are the only hue on screen, so a speaker can be told apart at a glance.
@immutable
class Tone extends ThemeExtension<Tone> {
  final Color base, sidebar, surface, ink, ink2, ink3, line;
  final Color bubble, raised, hover, menu, danger;
  final bool glass;
  final Color fillTop, fillBottom, bar, fieldFocus;
  final List<Color> orbs;
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
    this.glass = false,
    this.fillTop = Colors.transparent,
    this.fillBottom = Colors.transparent,
    this.bar = Colors.transparent,
    this.fieldFocus = Colors.transparent,
    this.orbs = const [],
  });
  static const light = Tone(
    base: Color(0xffffffff),
    sidebar: Color(0xfff7f7f7),
    surface: Color(0xffffffff),
    ink: Color(0xff000000),
    ink2: Color(0xff5c5c5c),
    ink3: Color(0xff767676),
    line: Color(0xffe6e6e6),
    bubble: Color(0xfff2f2f2),
    raised: Color(0xffeaeaea),
    hover: Color(0xfff0f0f0),
    menu: Color(0xffffffff),
    danger: Color(0xffc22f2f),
  );
  static const dark = Tone(
    base: Color(0xff000000),
    sidebar: Color(0xff101010),
    surface: Color(0xff161616),
    ink: Color(0xffffffff),
    ink2: Color(0xffb0b0b0),
    ink3: Color(0xff8c8c8c),
    line: Color(0xff2a2a2a),
    bubble: Color(0xff1c1c1c),
    raised: Color(0xff2a2a2a),
    hover: Color(0xff1e1e1e),
    menu: Color(0xff1c1c1c),
    danger: Color(0xffff8a80),
  );
  static const glassLight = Tone(
    glass: true,
    base: Color(0xffe6e6e9),
    sidebar: Colors.transparent,
    surface: Color(0x8cffffff),
    ink: Color(0xff0b0b0c),
    ink2: Color(0xa60b0b0c),
    ink3: Color(0x8c0b0b0c),
    line: Color(0x140b0b0c),
    bubble: Color(0x80ffffff),
    raised: Color(0x0f0b0b0c),
    hover: Color(0x0d0b0b0c),
    menu: Color(0xfff6f6f7),
    danger: Color(0xffc22f2f),
    fillTop: Color(0xbdffffff),
    fillBottom: Color(0x80ffffff),
    bar: Color(0x73f4f4f5),
    fieldFocus: Color(0xd9ffffff),
    orbs: [Color(0xffffffff), Color(0xffb9b9c1), Color(0xfff8f8fa)],
  );
  static const glassDark = Tone(
    glass: true,
    base: Color(0xff08080a),
    sidebar: Colors.transparent,
    surface: Color(0x17ffffff),
    ink: Color(0xfff6f6f7),
    ink2: Color(0xadf6f6f7),
    ink3: Color(0x85f6f6f7),
    line: Color(0x1cffffff),
    bubble: Color(0x14ffffff),
    raised: Color(0x14ffffff),
    hover: Color(0x12ffffff),
    menu: Color(0xff1b1b1f),
    danger: Color(0xffff8a80),
    fillTop: Color(0x1fffffff),
    fillBottom: Color(0x0dffffff),
    bar: Color(0x4d101013),
    fieldFocus: Color(0x2bffffff),
    orbs: [Color(0xff4c4c56), Color(0xff34343c), Color(0xff2c2c33)],
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
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final page = FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(.03, 0),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      ),
    );
    if (!context.tone.glass) return page;
    // Glass pages share one backdrop, so the outgoing page fades instead of
    // being covered.
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic),
      ),
      child: page,
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
  final text =
      (dark ? Typography.whiteMountainView : Typography.blackMountainView)
          .copyWith(
            headlineMedium: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: tone.ink,
            ),
            headlineSmall: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: tone.ink,
            ),
            titleLarge: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: tone.ink,
            ),
            titleMedium: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tone.ink,
            ),
            titleSmall: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tone.ink3,
            ),
            bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: tone.ink),
            bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: tone.ink),
            bodySmall: TextStyle(fontSize: 13, height: 1.4, color: tone.ink2),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            labelMedium: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tone.ink3,
            ),
          )
          .apply(fontFamily: 'Nunito', fontFamilyFallback: _sansFallback);
  InputBorder field(Color color) => frosted
      ? const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide.none,
        )
      : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color),
        );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
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
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 17),
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
    iconTheme: IconThemeData(color: tone.ink, size: 22),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tone.ink,
        disabledForegroundColor: tone.ink3,
        hoverColor: tone.hover,
        highlightColor: tone.hover,
        shape: const CircleBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: frosted
          ? WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? tone.fieldFocus
                  : tone.surface,
            )
          : tone.surface,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tone.ink,
        disabledForegroundColor: tone.ink3,
        side: BorderSide(color: tone.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tone.ink2,
        disabledForegroundColor: tone.ink3,
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tone.ink2,
      textColor: tone.ink,
      selectedColor: tone.ink,
      selectedTileColor: tone.raised,
      subtitleTextStyle: text.bodySmall,
      titleTextStyle: text.titleMedium,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: BorderSide(color: tone.ink3, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tone.ink
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(tone.base),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: tone.line),
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
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: ShapeDecoration(
        color: frosted ? tone.ink : tone.raised,
        shape: const StadiumBorder(),
      ),
      labelColor: frosted ? tone.base : tone.ink,
      unselectedLabelColor: tone.ink2,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tone.menu,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tone.line),
      ),
      textStyle: text.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(
        color: tone.ink,
        shape: const StadiumBorder(),
      ),
      textStyle: text.labelMedium?.copyWith(color: tone.base),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tone.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: tone.base),
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tone.menu,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    dividerTheme: DividerThemeData(color: tone.line, thickness: 1, space: 1),
  );
}

MarkdownStyleSheet markdownStyle(BuildContext context, {Color? color}) {
  final tone = context.tone;
  final ink = color ?? tone.ink;
  final body = Theme.of(context).textTheme.bodyMedium!.copyWith(color: ink);
  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(decoration: TextDecoration.underline),
    strong: body.copyWith(fontWeight: FontWeight.w800),
    em: body.copyWith(fontStyle: FontStyle.italic),
    h1: body.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3),
    h2: body.copyWith(fontSize: 19, fontWeight: FontWeight.w800, height: 1.3),
    h3: body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, height: 1.3),
    h4: body.copyWith(fontWeight: FontWeight.w800),
    h5: body.copyWith(fontWeight: FontWeight.w800),
    h6: body.copyWith(fontWeight: FontWeight.w800),
    listBullet: body,
    blockSpacing: 10,
    code: body.copyWith(
      fontFamily: monoFont,
      fontSize: 13,
      backgroundColor: tone.raised,
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: ShapeDecoration(
      color: tone.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    this.size = 38,
    this.working = false,
    this.twitch = false,
  });
  CatAvatar.of(
    Json bot, {
    super.key,
    this.size = 38,
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
    this.size = 38,
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

/// Three dots hopping in turn while a Bot is thinking.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});
  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var dot = 0; dot < 3; dot++)
          Transform.translate(
            offset: Offset(
              0,
              -2 *
                  (1 -
                      math.cos(
                        2 * math.pi * (controller.value - dot * .12 / .9),
                      )),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StatusDot(size: 5, color: context.tone.ink2),
            ),
          ),
      ],
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  final String text;
  const ErrorNotice(this.text, {super.key});
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
        ],
      ),
    );
  }
}

Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

class AsyncPane extends StatefulWidget {
  final Future<Json> Function() load;
  final Widget Function(BuildContext, Json, VoidCallback) builder;
  const AsyncPane({super.key, required this.load, required this.builder});
  @override
  State<AsyncPane> createState() => _AsyncPaneState();
}

class _AsyncPaneState extends State<AsyncPane> {
  late Future<Json> value = widget.load();
  void reload() => setState(() {
    value = widget.load();
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: value,
    builder: (context, snapshot) {
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
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) return const Center(child: Breathing());
      return widget.builder(context, snapshot.data!, reload);
    },
  );
}
