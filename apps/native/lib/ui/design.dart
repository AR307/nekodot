import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../data/client.dart';

final nativeRoutes = RouteObserver<ModalRoute<void>>();

const accent = Color(0xffe8603c);
const avatarColors = [
  '#E8603C',
  '#2F9E8F',
  '#6482C6',
  '#C287A3',
  '#D9932B',
  '#8B75AF',
  '#77A979',
  '#8C8376',
];
Color hexColor(String value) =>
    Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xfff07a55) : accent,
        surface: dark ? const Color(0xff211d18) : Colors.white,
        onSurface: dark ? const Color(0xfff3eee6) : const Color(0xff1f1b16),
        outlineVariant: dark
            ? const Color(0xff3a342c)
            : const Color(0xffe8e1d6),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff16130f)
        : const Color(0xfffaf7f2),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
  );
}

class CatAvatar extends StatelessWidget {
  final String color;
  final double size;
  const CatAvatar({super.key, this.color = '#E8603C', this.size = 38});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Bot',
    child: SvgPicture.string(
      '''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
    <path d="M7 21 6 7l13 8q5-2 10 0L42 7l-1 14q5 17-17 20Q2 38 7 21Z" fill="$color"/>
    <path d="M16 25v3m16-3v3" stroke="white" stroke-width="3.5" stroke-linecap="round"/>
    <path d="m21 32 3 2 3-2" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
    </svg>''',
      width: size,
      height: size,
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  final String text;
  const ErrorNotice(this.text, {super.key});
  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(child: SelectableText(text)),
            ],
          ),
        );
}

Future<T?> pushPage<T>(
  BuildContext context,
  Widget page,
) => Navigator.of(context).push<T>(
  PageRouteBuilder(
    pageBuilder: (_, animation, secondaryAnimation) => page,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, secondaryAnimation, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
  ),
);

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
                OutlinedButton(
                  onPressed: reload,
                  child: const Text('重试 / Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.builder(context, snapshot.data!, reload);
    },
  );
}
