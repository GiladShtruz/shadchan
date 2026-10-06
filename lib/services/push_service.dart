import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/services/personal_card_service.dart';

/// Push notifications from the server: the personal card's news only — an
/// access request, an answer to one, a friend's new card, a wedding, a Hebrew
/// birthday. Ordinary edits to a card never push anything; they show up in
/// the person's profile.
///
/// Started once Firebase is up and a durable account is signed in. Nothing
/// here runs under `flutter test`, where Firebase is never ready.
abstract final class PushService {
  static bool _started = false;
  static String? _token;
  static final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  static Future<void> start() async {
    if (_started || !FirebaseBootstrap.isReady) {
      return;
    }
    if (await PersonalCardService.durableUid() == null) {
      return;
    }
    _started = true;
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      final NotificationSettings settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      // On iOS there is no FCM token until APNs has handed one over, and
      // there never will be until an APNs key is uploaded to Firebase. Asking
      // for the FCM token before then throws; waiting quietly is right.
      if (Platform.isIOS && await messaging.getAPNSToken() == null) {
        _started = false;
        return;
      }

      final String? token = await messaging.getToken();
      if (token != null) {
        _token = token;
        await PersonalCardService.saveDeviceToken(token);
      }
      _subscriptions
        ..add(
          messaging.onTokenRefresh.listen((String fresh) {
            _token = fresh;
            unawaited(PersonalCardService.saveDeviceToken(fresh));
          }),
        )
        ..add(FirebaseMessaging.onMessage.listen(_showInForeground))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen(_open));

      // A push that started the app: Back from where it leads goes home.
      final RemoteMessage? initial = await messaging.getInitialMessage();
      if (initial != null) {
        _open(initial, launch: true);
      }
    } catch (error, stackTrace) {
      _started = false;
      debugPrint('PushService.start failed: $error\n$stackTrace');
    }
  }

  /// Marks the notice a tapped push was about as read. Set by the app.
  static void Function(String inboxId)? onNoticeOpened;

  /// The app is open: a small banner inside it, not a system notification.
  static void _showInForeground(RemoteMessage message) {
    final RemoteNotification? notification = message.notification;
    if (notification == null) {
      return;
    }
    NotificationService.onForegroundNotice?.call(
      notification.title ?? '',
      notification.body ?? '',
      routeOf(message.data),
    );
  }

  static void _open(RemoteMessage message, {bool launch = false}) {
    final Object? inboxId = message.data['inboxId'];
    if (inboxId is String && inboxId.isNotEmpty) {
      onNoticeOpened?.call(inboxId);
    }
    final String? route = routeOf(message.data);
    if (route != null) {
      NotificationService.openRoute(route, launch: launch);
    }
  }

  /// Where a push leads — the same place its row on the notifications page
  /// leads: a friend's new card opens their profile at the access request, an
  /// approval opens the card itself.
  @visibleForTesting
  static String? routeOf(Map<String, dynamic> data) {
    final String kind = data['kind'] as String? ?? '';
    final String owner = data['ownerUid'] as String? ?? '';
    final String hash = data['ownerPhoneHash'] as String? ?? '';
    final String? focus = switch (kind) {
      'cardCreated' => 'request',
      'accessApproved' => 'card',
      _ => null,
    };
    if (focus != null && owner.isNotEmpty) {
      return Uri(
        path: '/card-friend/$owner',
        queryParameters: <String, String>{
          if (hash.isNotEmpty) 'h': hash,
          'focus': focus,
        },
      ).toString();
    }
    final Object? route = data['route'];
    return route is String && route.startsWith('/') ? route : null;
  }

  /// Stops pushes to this device, for a sign-out: the next person on the
  /// phone must not receive the last one's news.
  static Future<void> stop() async {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final String? token = _token;
    _token = null;
    _started = false;
    if (token == null) {
      return;
    }
    await PersonalCardService.removeDeviceToken(token);
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('PushService.stop failed: $error');
    }
  }
}
