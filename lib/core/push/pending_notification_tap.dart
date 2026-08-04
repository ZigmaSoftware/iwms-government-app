import 'package:flutter/foundation.dart';

/// A push notification the user tapped, held until a screen can act on it.
///
/// FCM delivers a tap in three different situations — app foregrounded
/// (`onMessage` + our local notification), backgrounded
/// (`onMessageOpenedApp`), and launched from terminated
/// (`getInitialMessage`) — and in the last two the tap arrives before any
/// role screen is mounted, so there is nothing to navigate with yet.
///
/// Rather than thread a global navigator through GoRouter, taps are parked
/// here and the role shell drains them once it is built (see
/// `MainSupervisorTabBar`). A [ValueNotifier] so a shell that is already open
/// reacts immediately instead of only on next launch.
class PendingNotificationTap {
  PendingNotificationTap._();

  /// The most recent unhandled tap payload (the FCM `data` map), or null.
  ///
  /// Only the latest is kept: these are "take me to the thing" intents, and
  /// replaying a queue of stale ones would fight the user's navigation.
  static final ValueNotifier<Map<String, dynamic>?> pending =
      ValueNotifier<Map<String, dynamic>?>(null);

  static void record(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return;
    pending.value = data;
  }

  /// Take the pending tap, clearing it so it is handled exactly once.
  static Map<String, dynamic>? take() {
    final value = pending.value;
    if (value != null) pending.value = null;
    return value;
  }

  static void clear() => pending.value = null;
}
