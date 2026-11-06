import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/usage.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/statistics.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

// Requires the real isolated Node/Relay/Hermes and a configured real model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('account statistics on the native client', (tester) async {
    final c = NekodotClient();
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    const conversation = String.fromEnvironment('QA_CONVERSATION');
    if (Platform.isWindows) {
      await DesktopHost.initialize();
      tester.view.physicalSize = const Size(2800, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    Future<void> until(
      bool Function() ready,
      String stage, {
      int seconds = 300,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> tap(Finder finder) async {
      await until(
        () => finder.evaluate().isNotEmpty,
        'Control present',
        seconds: 30,
      );
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: .5,
      );
      await settle();
      await tester.tap(finder.first);
      await settle();
    }

    Future<void> scrollTop() async {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('usage-span-30')),
        -500,
        scrollable: find
            .descendant(
              of: find.byType(StatisticsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle();
    }

    bool converted = false;
    Future<void> shot(String name) async {
      await settle();
      final file = 'statistics-${Platform.operatingSystem}-$name';
      if (Platform.isAndroid) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(file);
      } else {
        await Directory(evidence).create(recursive: true);
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$evidence/$file.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
    }

    final login = await c.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    await until(
      () => c.online && c.node.conversations.isNotEmpty,
      'Real Node online',
    );
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    runApp(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, value, _) => MaterialApp(
          theme: appTheme(value ? Brightness.dark : Brightness.light),
          navigatorObservers: [nativeRoutes],
          builder: (context, child) => Platform.isWindows
              ? WindowChrome(child: child!)
              : Ambient(child: child!),
          home: HomePage(client: c),
        ),
      ),
    );
    await tap(find.byKey(const ValueKey('conversation-$conversation')));
    final input = find.byKey(const ValueKey('chat-input'));
    final before = (c.node.messages[conversation] ?? [])
        .map((m) => m['messageId'])
        .toSet();
    await tap(input);
    await tester.enterText(
      input,
      'Reply only with STATISTICS_${Platform.operatingSystem.toUpperCase()}_OK.',
    );
    await tap(find.byTooltip('发送'));
    await until(
      () => (c.node.messages[conversation] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['kind'] == 'text' &&
            m['status'] == 'done',
      ),
      'Real reply completed',
    );
    if (Platform.isAndroid) {
      await tester.pageBack();
      await settle();
    }
    if (find.byTooltip('账户').evaluate().isNotEmpty) {
      await tap(find.byTooltip('账户'));
      await tap(find.text('设置').last);
    } else {
      await tap(find.byTooltip('设置'));
    }
    await tap(find.byKey(const ValueKey('settings-statistics')));
    await until(
      () => find.byType(UsageCalendar).evaluate().isNotEmpty,
      'Statistics loaded',
    );
    await tap(find.byKey(const ValueKey('usage-refresh')));
    await until(
      () =>
          tester
              .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
              .onPressed !=
          null,
      'Refreshed',
    );
    var summary = tester.widget<UsageCalendar>(find.byType(UsageCalendar)).data;
    expect(summary.totals.total, greaterThan(0));
    expect(
      summary.conversations.any(
        (r) => r.entity['kind'] == 'group' && r.amount.total > 0,
      ),
      isTrue,
    );
    expect(
      summary.rows.fold<int>(0, (n, r) => n + r.amount.total),
      summary.totals.total,
    );
    final bytes = usageCsv(summary);
    expect(bytes.take(3), [239, 187, 191]);
    if (Platform.isWindows) {
      await File('$evidence/statistics-real-export.csv').writeAsBytes(bytes);
    }
    await shot('light');
    final day = summary.days.entries.last;
    await tap(find.byKey(ValueKey('usage-day-${day.key}')));
    expect(
      find.textContaining('${usageNumber(day.value.total)} Token'),
      findsWidgets,
    );
    await shot('calendar-detail');
    Tooltip.dismissAllToolTips();
    for (final entry in [summary.conversations.first, summary.routines.first]) {
      final row = find.byKey(
        ValueKey('usage-row-${entry.nodeId}-${entry.entity['id']}'),
      );
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: find
            .descendant(
              of: find.byType(StatisticsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await settle();
      if (Platform.isWindows) {
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(row));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.textContaining('${usageNumber(entry.amount.total)} Token'),
          findsWidgets,
        );
        await shot(
          entry.entity['kind'] == 'routine' ? 'routine-detail' : 'dot-detail',
        );
        await mouse.removePointer();
      } else {
        await tap(row);
        expect(
          find.textContaining('${usageNumber(entry.amount.total)} Token'),
          findsWidgets,
        );
        await shot(
          entry.entity['kind'] == 'routine' ? 'routine-detail' : 'dot-detail',
        );
      }
      Tooltip.dismissAllToolTips();
    }
    await scrollTop();
    await tap(find.byType(DropdownButton<String>));
    await tap(find.text('Usage Windows').last);
    await until(
      () =>
          tester
              .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
              .onPressed !=
          null,
      'Node filter loaded',
    );
    expect(
      tester.widget<UsageCalendar>(find.byType(UsageCalendar)).data.nodes,
      hasLength(1),
    );
    await tap(find.byType(DropdownButton<String>));
    await tap(find.text('全部电脑').last);
    await until(
      () =>
          tester
              .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
              .onPressed !=
          null,
      'Account loaded',
    );
    await tap(find.byKey(const ValueKey('usage-span-7')));
    await until(
      () =>
          tester
              .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
              .onPressed !=
          null,
      'Range loaded',
    );
    summary = tester.widget<UsageCalendar>(find.byType(UsageCalendar)).data;
    expect(summary.to.difference(summary.from).inDays, 6);
    await tap(find.byKey(const ValueKey('usage-span-0')));
    await until(
      () =>
          find.byTooltip('上一年').evaluate().isNotEmpty &&
          tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('usage-refresh')),
                  )
                  .onPressed !=
              null,
      'All-years calendar',
    );
    dark.value = true;
    await settle();
    await shot('dark');
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('usage-routines'))),
      alignment: 1,
    );
    await shot('dark-breakdown');
    c.language = 'en';
    dark.value = false;
    await settle();
    await scrollTop();
    await tap(find.byKey(const ValueKey('usage-span-30')));
    await until(
      () =>
          tester
              .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
              .onPressed !=
          null,
      'English range loaded',
    );
    await shot('english');
    if (Platform.isWindows) {
      tester.view.physicalSize = const Size(780, 1688);
      await shot('narrow');
      tester.view.physicalSize = const Size(2800, 1800);
    }
    if (const bool.fromEnvironment('QA_MANUAL_EXPORT')) {
      final snapshot = tester
          .widget<UsageCalendar>(find.byType(UsageCalendar))
          .data;
      await tap(find.byKey(const ValueKey('usage-export')));
      final target = File(
        '${const String.fromEnvironment('QA_WORK_DIR')}/statistics-system-export.csv',
      );
      await until(() => target.existsSync(), 'System CSV saved');
      expect(await target.readAsBytes(), usageCsv(snapshot));
    }
    expect(tester.takeException(), isNull);
  });
}
