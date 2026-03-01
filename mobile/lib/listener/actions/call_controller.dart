import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/livekit_service.dart';
import '../../services/socket_service.dart';
import '../../services/call_service.dart';
import '../../services/incoming_call_overlay_service.dart';
import '../../services/active_call_service.dart';

/// Single source of truth for call state.
/// UI renders strictly based on this enum — no multi-flag toggling.
enum CallState { calling, connecting, connected, ended }

/// Controller that owns all call logic, streams, and lifecycle.
/// Widget only listens and renders — zero business logic in the UI.
class CallController extends ChangeNotifier {
  // ── Constructor params ──
  final String? callerName;
  final String? callerAvatar;
  final String? channelName;
  final String? callId;
  final String? callerId;

  /// When [isAccepted] is true the listener already accepted the incoming
  /// call, so the controller starts in [CallState.connecting] immediately
  /// (skipping the "Calling…" state and its connecting sound).
  final bool isAccepted;

  CallController({
    this.callerName,
    this.callerAvatar,
    this.channelName,
    this.callId,
    this.callerId,
    this.isAccepted = false,
  });

  // ── Services (singletons) ──
  final LiveKitService _livekitService = LiveKitService();
  final SocketService _socketService = SocketService();
  final CallService _callService = CallService();
  final ActiveCallService _activeCallService = ActiveCallService();

  // ── Audio ──
  late final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Subscriptions (cancel in dispose) ──
  StreamSubscription? _callConnectedSub;
  StreamSubscription? _callEndedSub;

  // ── State ── (initial value set in constructor body via isAccepted)
  late CallState _callState;
  CallState get callState => _callState;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  int _callDuration = 0;
  int get callDuration => _callDuration;

  String? _connectionError;
  String? get connectionError => _connectionError;

  String? _resolvedChannel;

  Timer? _callTimer;
  bool _disposed = false;

  // Initialize _callState based on whether call was already accepted
  // (delayed init because 'isAccepted' is a final field set in constructor)
  CallState _resolveInitialState() =>
      isAccepted ? CallState.connecting : CallState.calling;

  // ── Public helpers ──
  String get formattedDuration {
    final mins = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDuration % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get statusText {
    switch (_callState) {
      case CallState.calling:
        return 'Calling…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.connected:
        return formattedDuration;
      case CallState.ended:
        return 'Call Ended';
    }
  }

  // ── Lifecycle ──

  /// Call once from initState. Sets up listeners, audio, Agora.
  Future<void> initialize() async {
    _activeCallService.initialize();
    _callState = _resolveInitialState();
    _setupSocketListeners();
    await _persistActiveCallSession();
    // Only play connecting beep if the call hasn't been accepted yet
    if (!isAccepted) {
      _playConnectingSound();
    }
    await _initLiveKit();
  }

  Map<String, dynamic> _buildActiveCallSession() {
    final effectiveCallId = callId ?? channelName ?? _resolvedChannel ?? '';
    return {
      'role': 'listener',
      'is_ongoing': _callState != CallState.ended,
      'call_id': effectiveCallId,
      'channel_name': _resolvedChannel ?? channelName ?? effectiveCallId,
      'caller_user_id': callerId,
      'peer_name': callerName,
      'peer_avatar': callerAvatar,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _persistActiveCallSession() async {
    final callIdForSession = callId ?? channelName ?? _resolvedChannel;
    if (callIdForSession == null || callIdForSession.isEmpty) return;
    await _activeCallService.saveActiveCallSession(_buildActiveCallSession());
  }

  // ── Socket listeners (single subscription each) ──

  void _setupSocketListeners() {
    _callConnectedSub = _socketService.onCallConnected.listen((data) {
      debugPrint('CallController: socket call:connected received');
      _transitionTo(CallState.connected);
    });

    _callEndedSub = _socketService.onCallEnded.listen((data) {
      final reason = data['reason']?.toString() ?? 'unknown';
      final code = data['code']?.toString() ?? '';
      debugPrint('CallController: socket call:ended – reason=$reason code=$code');

      // Handle server-initiated balance exhaustion (caller's wallet ran out)
      if (reason == 'balance_exhausted' || code == 'MAX_DURATION_REACHED' || code == 'ZERO_BALANCE') {
        debugPrint('[CALL-L] Caller balance exhausted — disconnecting');
      }

      endCall();
    });
  }

  // ── Internal state machine ──

  /// Moves to a new state only if the transition is valid.
  /// Prevents backward transitions and duplicate updates.
  void _transitionTo(CallState next) {
    if (_disposed) return;
    if (_callState == next) return;
    // Only forward transitions allowed (calling→connecting→connected→ended)
    if (next.index <= _callState.index && next != CallState.ended) return;

    debugPrint('CallController: $_callState → $next');
    _callState = next;

    if (next == CallState.connected) {
      _stopAudio();
      _startCallTimer();
      unawaited(_persistActiveCallSession());
    } else if (next == CallState.ended) {
      _stopAudio();
      _callTimer?.cancel();
    }

    notifyListeners();
  }

  // ── Audio ──

  Future<void> _playConnectingSound() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('voice/sample.mp3'));
      // Stop after 2 s — just a notification beep, not a ringtone
      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed && _callState != CallState.connected) {
          _audioPlayer.stop();
        }
      });
    } catch (e) {
      debugPrint('CallController: audio play error: $e');
    }
  }

  void _stopAudio() {
    try {
      _audioPlayer.stop();
    } catch (_) {}
  }

  // ── LiveKit init + join ──

  Future<void> _initLiveKit() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setError('Microphone permission denied');
      return;
    }

    final channel = channelName ?? callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('CallController: joining room $channel');

    // Fetch token
    final tokenResult = await _livekitService.fetchToken(roomName: channel);
    if (!tokenResult.success || tokenResult.token == null || tokenResult.url == null) {
      _setError(tokenResult.error ?? 'Failed to get call token');
      _scheduleAutoClose();
      return;
    }

    // Join room
    final joined = await _livekitService.connectToRoom(
      url: tokenResult.url!,
      token: tokenResult.token!,
    );

    if (joined) {
      // Register LiveKit event handler
      _livekitService.room?.events.listen((event) {
        if (event is ParticipantConnectedEvent) {
          debugPrint('CallController: remote user joined');
          _transitionTo(CallState.connected);
        } else if (event is ParticipantDisconnectedEvent) {
          debugPrint('CallController: remote user left');
          endCall();
        } else if (event is RoomDisconnectedEvent) {
          debugPrint('CallController: room disconnected ${event.reason}');
          if (_callState != CallState.connected && !_disposed) {
            _setError('Call error: Disconnected');
            endCall();
          }
        }
      });
    }

    if (!joined) {
      _setError('Failed to join call');
      _scheduleAutoClose();
    } else {
      _stopAudio();
      _transitionTo(CallState.connecting);

      _resolvedChannel = channel;
      await _persistActiveCallSession();
      _socketService.joinedChannel(
        callId: callId ?? channel,
        channelName: channel,
      );
    }
  }

  // ── User actions ──

  void toggleMute() {
    if (_disposed) return;
    _isMuted = !_isMuted;
    _livekitService.muteLocalAudio(_isMuted);
    notifyListeners();
  }

  /// End the call. Safe to call multiple times — no-ops after first.
  Future<void> endCall() async {
    if (_callState == CallState.ended) return;

    // Capture state before transitioning
    final wasConnected = _callState == CallState.connected;
    final durationSnapshot = _callDuration;

    // 1. Stop timer & audio IMMEDIATELY
    _callTimer?.cancel();
    _callTimer = null;
    _stopAudio();
    _transitionTo(CallState.ended);

    // 2. Disconnect LiveKit FIRST — stops audio instantly for both sides
    debugPrint('[CALL-L] Disconnecting LiveKit room');
    await _livekitService.reset();

    // 3. Notify peer via socket IMMEDIATELY
    if (callerId != null && _resolvedChannel != null) {
      _socketService.endCall(
        callId: callId ?? _resolvedChannel!,
        otherUserId: callerId!,
      );
    }
    if (_resolvedChannel != null) {
      _socketService.leftChannel(channelName: _resolvedChannel!);
    }

    // 4. Update backend (billing / status) — can happen after disconnect
    debugPrint('[CALL-L] Updating backend');
    final cid = callId ?? _resolvedChannel;
    if (cid != null) {
      try {
        final status = wasConnected || durationSnapshot > 0
            ? 'completed'
            : 'cancelled';
        if (status == 'completed') {
          await _callService.endCall(
            callId: cid,
            durationSeconds: durationSnapshot,
          );
        } else {
          await _callService.updateCallStatus(
            callId: cid,
            status: status,
            durationSeconds: durationSnapshot > 0 ? durationSnapshot : null,
          );
        }
      } catch (e) {
        debugPrint('[CALL-L] Backend update error: $e');
      }
    }
    debugPrint('[CALL-L] Cleanup done');

    await _activeCallService.clearActiveCallSession();

    // 5. Clear active call flag so listener can receive new incoming calls
    IncomingCallOverlayService().clearActiveCall();
  }

  // ── Internals ──

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _callDuration++;
      notifyListeners();
    });
  }

  void _setError(String msg) {
    if (_disposed) return;
    _connectionError = msg;
    _stopAudio();
    notifyListeners();
  }

  void _scheduleAutoClose() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed) endCall();
    });
  }

  // ── Dispose ──

  @override
  void dispose() {
    _disposed = true;
    _callConnectedSub?.cancel();
    _callEndedSub?.cancel();
    _callTimer?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    // LiveKit disconnect logic handles everything
    super.dispose();
  }
}
