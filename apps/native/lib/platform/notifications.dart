import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../data/client.dart';

/// Android delivery is exclusively FCM; Windows uses its live account channel.
/// Hermes/Node decide when a task is done. This class only displays and opens it.
class NativeNotifications {
  final NekodotClient client;
  NativeNotifications(this.client);
  final local = FlutterLocalNotificationsPlugin();
  final subscriptions = <StreamSubscription<dynamic>>[];
  final seen = <String>{};
  String? boundSession, deviceId;
  String? pushTarget;
  Completer<String>? registration;
  bool initialized = false, registering = false, disposed = false;

  Future<void> initialize(BuildContext context) async {
    try {
      await local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'nekodot',
            appUserModelId: 'app.nekodot.client',
            guid: 'be9da93d-47b6-4987-a955-cee671680353',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null) {
            client.openNotification(object(jsonDecode(response.payload!)));
          }
        },
      );
      final launch = await local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse?.payload != null) {
        client.openNotification(
          object(jsonDecode(launch!.notificationResponse!.payload!)),
        );
      }
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('notification-requested') && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(client.tr('开启任务通知', 'Stay updated')),
            content: Text(
              client.tr(
                '收到 Bot 回复、提问和审批时提醒你。通知将显示 Bot 或群组名称与回复预览；可在系统设置关闭。',
                'Get replies, questions and approvals. Notifications show the Bot or group name and a reply preview. You can disable them in system settings.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(client.tr('继续', 'Continue')),
              ),
            ],
          ),
        );
        await prefs.setBool('notification-requested', true);
        if (Platform.isAndroid) {
          await Firebase.initializeApp();
          await FirebaseMessaging.instance.requestPermission();
        }
      }
      if (Platform.isAndroid) {
        await Firebase.initializeApp();
        await local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'nekodot_tasks',
                'nekodot tasks',
                description: 'Task replies, questions and approvals',
                importance: Importance.high,
              ),
            );
        deviceId = prefs.getString('notification-device') ?? uid();
        await prefs.setString('notification-device', deviceId!);
        subscriptions.add(
          FirebaseMessaging.instance.onRegistered.listen((target) {
            pushTarget = target;
            if (registration?.isCompleted == false) {
              registration!.complete(target);
            }
            boundSession = null;
            unawaited(register());
          }),
        );
        subscriptions.add(
          FirebaseMessaging.onMessage.listen((message) {
            unawaited(show(message.data));
          }),
        );
        subscriptions.add(
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
            seen.add('${message.data['notificationId']}');
            client.openNotification(message.data);
          }),
        );
        final message = await FirebaseMessaging.instance.getInitialMessage();
        if (message != null) {
          seen.add('${message.data['notificationId']}');
          client.openNotification(message.data);
        }
      } else if (Platform.isWindows) {
        subscriptions.add(
          client.notifications.stream.listen((signal) {
            unawaited(show(signal));
          }),
        );
      }
      initialized = true;
      client.addListener(onClientChange);
      await register();
    } catch (_) {
      client.setNotificationState(
        failure: client.tr(
          '系统通知不可用。请检查通知权限；Android 还需要可用的 Google 服务。',
          'System notifications are unavailable. Check permission; Android also requires Google services.',
        ),
      );
    }
  }

  void onClientChange() {
    if (!disposed && client.token != boundSession) unawaited(register());
  }

  Future<void> register() async {
    if (!initialized || disposed || registering) return;
    registering = true;
    try {
      if (client.token == null) {
        boundSession = null;
        seen.clear();
        return;
      }
      if (Platform.isAndroid) {
        final permission = await FirebaseMessaging.instance
            .getNotificationSettings();
        if (permission.authorizationStatus != AuthorizationStatus.authorized) {
          client.notificationStatus = client.tr(
            '通知未授权，请在系统设置中开启',
            'Allow notifications in system settings',
          );
          boundSession = client.token;
          return;
        }
        final status = await client.request('/notifications/status');
        if (status['available'] != true) {
          throw StateError('Relay push unavailable');
        }
        if (pushTarget == null) {
          registration = Completer<String>();
          await FirebaseMessaging.instance.register();
          pushTarget = await registration!.future.timeout(
            const Duration(seconds: 20),
          );
        }
        await client.request(
          '/devices',
          method: 'POST',
          body: {
            'deviceId': deviceId,
            'token': pushTarget,
            'platform': 'android',
          },
        );
      }
      boundSession = client.token;
      client.notificationStatus = client.tr('通知已开启', 'Notifications enabled');
      client.notificationError = '';
    } catch (_) {
      // Retry on the next foreground/network recovery, not every chat delta.
      boundSession = client.token;
      client.notificationError = client.tr(
        '通知连接失败，请返回前台后重试',
        'Notification connection failed. Reopen to retry.',
      );
    } finally {
      registering = false;
      if (!disposed) client.setNotificationState();
    }
  }

  Future<void> show(Json signal) async {
    try {
      if (disposed ||
          client.token == null ||
          !seen.add('${signal['notificationId']}')) {
        return;
      }
      final focused = !Platform.isWindows || await windowManager.isFocused();
      if (focused &&
          client.active &&
          client.selectedNodeId == signal['nodeId'] &&
          client.visibleConversation == signal['conversationId']) {
        return;
      }
      await local.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
        title: '${signal['displayName']}',
        body: '${signal['preview']}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'nekodot_tasks',
            'nekodot tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(signal),
      );
    } catch (_) {
      if (!disposed) {
        client.setNotificationState(
          failure: client.tr(
            '无法显示系统通知，请检查系统设置',
            'Cannot show a notification. Check system settings.',
          ),
        );
      }
    }
  }

  void dispose() {
    disposed = true;
    client.removeListener(onClientChange);
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
