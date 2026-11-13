import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/client.dart';
import '../ui/design.dart';

/// Your initial on a disc: the mark of the account.
class AccountMark extends StatelessWidget {
  final NekodotClient client;
  final double size;

  /// On the black rail the disc is white.
  final bool onRail;
  const AccountMark({
    super.key,
    required this.client,
    required this.size,
    this.onRail = false,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final name = '${client.account.me?['user']['email'] ?? ''}'
        .split('@')
        .first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onRail ? Colors.white : tone.ink,
      ),
      child: Text(
        name.isEmpty ? '' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: onRail ? Colors.black : tone.base,
          fontSize: size * .42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// You, and the few things changed often: language, appearance and
/// notifications; then the ways into settings and statistics, and signing
/// out. It is the body of the account menu on a desktop and of the account
/// sheet on a phone.
class AccountQuick extends StatelessWidget {
  final NekodotClient client;

  /// Closes the menu or sheet it is shown in.
  final VoidCallback close;
  final VoidCallback onSettings, onStatistics, onSignOut;
  const AccountQuick({
    super.key,
    required this.client,
    required this.close,
    required this.onSettings,
    required this.onStatistics,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client,
    builder: (context, _) {
      final c = client, tone = context.tone, text = Theme.of(context).textTheme;
      final email = '${c.account.me?['user']['email'] ?? ''}';
      final height = tone.glass ? 52.0 : 40.0;
      final divider = Divider(
        height: 9,
        thickness: Tone.hair,
        indent: 12,
        endIndent: 12,
        color: tone.line,
      );
      // A row that only holds a control: its label, then the control.
      Widget pref(IconData icon, String label, Widget end) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Icon(icon, size: 18, color: tone.ink2),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: text.bodyMedium)),
              end,
            ],
          ),
        ),
      );
      // A row that goes somewhere, or does one thing.
      Widget go(
        String key,
        IconData icon,
        String label,
        VoidCallback onTap, {
        Widget? end,
      }) => InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(Tone.r8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                Icon(icon, size: 18, color: tone.ink2),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: text.bodyMedium)),
                ?end,
              ],
            ),
          ),
        ),
      );
      final next = Icon(Symbols.chevron_right, size: 18, color: tone.ink3);
      return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  AccountMark(client: c, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          email.split('@').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: tone.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            divider,
            pref(
              Symbols.language,
              c.tr('语言', 'Language'),
              Segment<String>(
                value: c.prefs.language,
                options: const {'zh': Text('中'), 'en': Text('EN')},
                onChanged: (value) => c.prefs.update(locale: value),
              ),
            ),
            pref(
              Symbols.contrast,
              c.tr('外观', 'Appearance'),
              Segment<String>(
                value: c.prefs.theme,
                options: {
                  'system': Tooltip(
                    message: c.tr('跟随系统', 'System'),
                    child: const Icon(Symbols.brightness_auto),
                  ),
                  'light': Tooltip(
                    message: c.tr('浅色', 'Light'),
                    child: const Icon(Symbols.light_mode),
                  ),
                  'dark': Tooltip(
                    message: c.tr('深色', 'Dark'),
                    child: const Icon(Symbols.dark_mode),
                  ),
                },
                onChanged: (value) => c.prefs.update(appearance: value),
              ),
            ),
            go(
              'account-notifications',
              Symbols.notifications,
              c.tr('通知', 'Notifications'),
              () async {
                final opened = await FlutterLocalNotificationsPlugin()
                    .openAppNotificationSettings();
                if (opened != true && context.mounted) {
                  showNotice(
                    context,
                    c.tr(
                      '请在系统设置中开启通知',
                      'Allow notifications in system settings',
                    ),
                  );
                }
              },
              end: StatusDot(
                on:
                    c.notificationError.isEmpty &&
                    c.notificationStatus.isNotEmpty,
              ),
            ),
            divider,
            go(
              'account-settings',
              Symbols.settings,
              c.tr('设置', 'Settings'),
              () {
                close();
                onSettings();
              },
              end: next,
            ),
            go(
              'account-statistics',
              Symbols.bar_chart,
              c.tr('统计', 'Statistics'),
              () {
                close();
                onStatistics();
              },
              end: next,
            ),
            divider,
            go(
              'account-sign-out',
              Symbols.logout,
              c.tr('退出账号', 'Sign out'),
              () {
                close();
                onSignOut();
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}
