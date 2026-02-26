import 'dart:async';

import 'call_service.dart';
import 'call_foreground_service.dart';
import 'socket_service.dart';
import 'storage_service.dart';

/// Maintains active-call session state across app lifecycle transitions.
class ActiveCallService {
  static final ActiveCallService _instance = ActiveCallService._internal();
  factory ActiveCallService() => _instance;
  ActiveCallService._internal();

  final StorageService _storage = StorageService();
  final CallService _callService = CallService();
  final SocketService _socketService = SocketService();
  final CallForegroundService _foregroundService = CallForegroundService();

  bool _initialized = false;
  bool _callScreenVisible = false;
  StreamSubscription? _callEndedSub;
  StreamSubscription? _callRejectedSub;
  StreamSubscription? _callFailedSub;

  bool get isCallScreenVisible => _callScreenVisible;

  void setCallScreenVisible(bool visible) {
    _callScreenVisible = visible;
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _callEndedSub = _socketService.onCallEnded.listen((_) async {
      await clearActiveCallSession();
    });
    _callRejectedSub = _socketService.onCallRejected.listen((_) async {
      await clearActiveCallSession();
    });
    _callFailedSub = _socketService.onCallFailed.listen((_) async {
      await clearActiveCallSession();
    });
  }

  Future<void> saveActiveCallSession(
    Map<String, dynamic> session, {
    bool updateNotification = true,
  }) async {
    await _storage.saveActiveCallSession(session);
    if (updateNotification) {
      final peerName = (session['peer_name']?.toString().trim().isNotEmpty ?? false)
          ? session['peer_name'].toString()
          : 'Active call';
      await _foregroundService.start(
        title: 'Call in Progress',
        text: '$peerName - Tap to return',
      );
    }
  }

  Future<void> updateActiveCallSession(
    Map<String, dynamic> patch, {
    bool updateNotification = false,
  }) async {
    final current = await _storage.getActiveCallSession() ?? <String, dynamic>{};
    final updated = <String, dynamic>{...current, ...patch};
    await saveActiveCallSession(
      updated,
      updateNotification: updateNotification,
    );
  }

  Future<Map<String, dynamic>?> getActiveCallSession() async {
    return _storage.getActiveCallSession();
  }

  Future<Map<String, dynamic>?> getValidatedActiveCallSession() async {
    final session = await _storage.getActiveCallSession();
    if (session == null) return null;

    final callId = session['call_id']?.toString();
    if (callId == null || callId.isEmpty) {
      await clearActiveCallSession();
      return null;
    }

    try {
      final result = await _callService.getCallById(callId);
      // If API request fails (network, temporary issue), keep local session.
      if (!result.success) return session;

      final call = result.call;
      if (call == null || !call.isActive) {
        await clearActiveCallSession();
        return null;
      }
    } catch (_) {
      // Keep local session if validation can't be completed right now.
      return session;
    }

    return session;
  }

  Future<void> clearActiveCallSession({bool stopForeground = true}) async {
    await _storage.clearActiveCallSession();
    if (stopForeground) {
      await _foregroundService.stop();
    }
  }

  Future<void> dispose() async {
    await _callEndedSub?.cancel();
    await _callRejectedSub?.cancel();
    await _callFailedSub?.cancel();
    _initialized = false;
  }
}
