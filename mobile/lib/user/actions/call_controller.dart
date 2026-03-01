import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/livekit_service.dart';
import '../../services/socket_service.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import '../../services/active_call_service.dart';

/// Single source of truth for call state on the USER side.
/// UI renders strictly based on this enum — no multi-flag toggling.
enum UserCallState { calling, connecting, connected, ended }

/// Controller that owns all call logic for the user-side calling screen.
/// Widget only listens and renders — zero business logic in the UI.
class UserCallController extends ChangeNotifier {
  // ── Constructor params ──
  final String callerName;
  final String callerAvatar;
  final String userName;
  final String? userAvatar;
  final String? channelName;
  final String? listenerId;
  final String? listenerDbId;
  final String? topic;
  final String? language;
  final String? gender;

  UserCallController({
    required this.callerName,
    required this.callerAvatar,
    this.userName = 'You',
    this.userAvatar,
    this.channelName,
    this.listenerId,
    this.listenerDbId,
    this.topic,
    this.language,
    this.gender,
  });

  // ── Services (singletons) ──
  final LiveKitService _livekitService = LiveKitService();
  final SocketService _socketService = SocketService();
  final CallService _callService = CallService();
  final UserService _userService = UserService();
  final ActiveCallService _activeCallService = ActiveCallService();

  // ── Audio ──
  late final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Subscriptions (cancel in dispose) ──
  StreamSubscription? _callConnectedSub;
  StreamSubscription? _callEndedSub;
  StreamSubscription? _callRejectedSub;
  StreamSubscription? _callBusySub;

  // ── State ──
  UserCallState _callState = UserCallState.calling;
  UserCallState get callState => _callState;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  int _callDuration = 0;
  int get callDuration => _callDuration;

  String? _connectionError;
  String? get connectionError => _connectionError;

  String? _currentChannelName;
  String? _callId;

  String? get callId => _callId ?? _currentChannelName;

  Timer? _callTimer;
  Timer? _noAnswerTimer;
  bool _disposed = false;
  bool _isCallEnding = false;
  Completer<void>? _endCallCompleter;

  /// Maximum seconds the wallet can afford (sent by server)
  int _maxAllowedSeconds = 0;
  int get maxAllowedSeconds => _maxAllowedSeconds;

  /// Remaining seconds before auto-disconnect (counts down from maxAllowedSeconds)
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;

  /// Reason the call ended (user_end, balance_zero, remote_end, network_drop).
  String? _endReason;
  String? get endReason => _endReason;

  /// True once endCall() has been entered (prevents double execution).
  bool get isCallEnding => _isCallEnding;

  /// Await this future after calling endCall() to wait for full cleanup.
  Future<void> get endCallFuture => _endCallCompleter?.future ?? Future.value();

  CallBillingSummary? _billingSummary;
  CallBillingSummary? get billingSummary => _billingSummary;

  // ── Public helpers ──
  String get formattedDuration {
    final mins = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDuration % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }


  String get statusText {
    if (_connectionError != null) return _connectionError!;
    switch (_callState) {
      case UserCallState.calling:
        return 'Calling…';
      case UserCallState.connecting:
        return 'Connecting…';
      case UserCallState.connected:
        return formattedDuration;
      case UserCallState.ended:
        return 'Call Ended';
    }
  }

  // ── Lifecycle ──

  /// Call once from initState.
  Future<void> initialize() async {
    _activeCallService.initialize();
    _setupSocketListeners();
    _playRingtone(); // fire-and-forget - don't block call setup

    if (channelName != null) {
      // Backward compatibility: channel already created
      _callId = channelName;
      await _persistActiveCallSession();
      await _initLiveKit();
    } else {
      await _initiateCallAndConnect();
    }
  }

  Map<String, dynamic> _buildActiveCallSession() {
    final effectiveCallId = _callId ?? channelName ?? _currentChannelName ?? '';
    return {
      'role': 'user',
      'is_ongoing': _callState != UserCallState.ended,
      'call_id': effectiveCallId,
      'channel_name': _currentChannelName ?? channelName ?? effectiveCallId,
      'listener_user_id': listenerId,
      'listener_db_id': listenerDbId,
      'peer_name': callerName,
      'peer_avatar': callerAvatar,
      'user_name': userName,
      'user_avatar': userAvatar,
      'topic': topic,
      'language': language,
      'gender': gender,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _persistActiveCallSession() async {
    final callIdForSession = _callId ?? channelName ?? _currentChannelName;
    if (callIdForSession == null || callIdForSession.isEmpty) return;
    await _activeCallService.saveActiveCallSession(_buildActiveCallSession());
  }

  // ── Socket listeners (single subscription each) ──

  void _setupSocketListeners() {
    _callConnectedSub = _socketService.onCallConnected.listen((data) {
      debugPrint('UserCallController: socket call:connected received');
      // Parse server-provided max allowed seconds for wallet-based auto-disconnect
      final maxSec = data['maxAllowedSeconds'];
      if (maxSec != null && maxSec is num && maxSec > 0) {
        _maxAllowedSeconds = maxSec.toInt();
        _remainingSeconds = _maxAllowedSeconds;
        debugPrint('[CALL] Server max allowed: ${_maxAllowedSeconds}s');
      } else {
        debugPrint('[CALL] No maxAllowedSeconds from server, using fallback balance check');
      }
      _transitionTo(UserCallState.connected);
    });

    _callEndedSub = _socketService.onCallEnded.listen((data) {
      debugPrint('UserCallController: socket call:ended – ${data['reason'] ?? 'unknown'}');
      final reason = data['reason']?.toString() ?? 'remote_end';
      final code = data['code']?.toString() ?? '';

      // Server-initiated balance exhaustion disconnect
      if (reason == 'balance_exhausted' || code == 'MAX_DURATION_REACHED' || code == 'ZERO_BALANCE') {
        debugPrint('[CALL] Server: balance exhausted, auto-ending');
        endCall(reason: 'balance_zero');
        return;
      }

      if (data['code'] == 'LISTENER_OFFLINE') {
        _setError(data['error'] ?? 'Listener is offline');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) endCall(reason: 'remote_end');
        });
      } else {
        endCall(reason: 'remote_end');
      }
    });

    _callRejectedSub = _socketService.onCallRejected.listen((data) {
      debugPrint('UserCallController: call rejected');
      _setError('Call was declined');
      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed) endCall(reason: 'remote_end');
      });
    });

    // Handle call:busy — listener is already on another call
    _callBusySub = _socketService.onCallBusy.listen((data) {
      debugPrint('UserCallController: listener is busy');
      _stopRingtone();
      _setError('Listener is busy on another call. Please try later.');
      Future.delayed(const Duration(seconds: 3), () {
        if (!_disposed) endCall(reason: 'listener_busy');
      });
    });

    // VERIFICATION: Handle call:failed events for verification failures
    _socketService.onCallFailed.listen((data) {
      debugPrint('UserCallController: call failed – ${data['reason'] ?? 'unknown'}');
      final reason = data['reason']?.toString() ?? '';
      final message = data['message']?.toString();
      
      // Handle listener verification failure
      if (reason == 'listener_not_approved') {
        _setError(message ?? 'This listener is not available for calls at the moment');
      } else if (reason == 'listener_offline') {
        _setError('Listener is currently offline');
      } else if (reason == 'verification_check_failed') {
        _setError('Unable to verify listener status. Please try again');
      } else {
        _setError(message ?? 'Call failed. Please try again');
      }
      
      _stopRingtone();
      Future.delayed(const Duration(seconds: 3), () {
        if (!_disposed) endCall(reason: 'remote_end');
      });
    });
  }

  // ── Internal state machine ──

  /// Moves forward only. Prevents backward transitions and duplicate updates.
  void _transitionTo(UserCallState next) {
    if (_disposed) return;
    if (_callState == next) return;
    // Only forward transitions allowed (calling→connecting→connected→ended)
    if (next.index <= _callState.index && next != UserCallState.ended) return;

    debugPrint('UserCallController: $_callState → $next');
    _callState = next;

    if (next == UserCallState.connected) {
      _stopRingtone();
      _noAnswerTimer?.cancel();
      _startCallTimer();
      unawaited(_persistActiveCallSession());
    } else if (next == UserCallState.ended) {
      _stopRingtone();
      _noAnswerTimer?.cancel();
      _callTimer?.cancel();
    }

    notifyListeners();
  }

  // ── Call initiation ──

  Future<void> _initiateCallAndConnect() async {
    debugPrint('UserCallController: Initiating call to listener...');

    // 1. Ensure socket is connected & request mic permission in parallel
    final socketFuture = _socketService.connect();
    final micFuture = Permission.microphone.request();

    final connected = await socketFuture;
    if (!connected) {
      _setError('Failed to connect. Please try again.');
      return;
    }

    // 2. Create call record via HTTP API
    final callResult = await _callService.initiateCall(
      listenerId: listenerDbId ?? listenerId ?? '',
      callType: 'audio',
    );

    if (!callResult.success) {
      _setError(callResult.error ?? 'Failed to initiate call');
      _stopRingtone();
      _scheduleAutoClose();
      return;
    }

    _callId = callResult.call!.callId;
    debugPrint('UserCallController: Call created with ID: $_callId');
    await _persistActiveCallSession();

    // 3. IMMEDIATELY notify listener via socket (before LiveKit setup)
    final targetUserId = listenerId;
    if (targetUserId != null && _callId != null) {
      _socketService.initiateCall(
        callId: _callId!,
        listenerId: targetUserId,
        callerName: userName,
        callerAvatar: userAvatar,
        topic: topic ?? 'General',
        language: language ?? 'English',
        gender: gender,
      );
    }

    // 4. Init LiveKit (mic permission already resolved in parallel)
    final micStatus = await micFuture;
    if (!micStatus.isGranted) {
      _setError('Microphone permission denied');
      return;
    }
    await _initLiveKitEngine();
  }

  // ── LiveKit init + join ──

  Future<void> _initLiveKit() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setError('Microphone permission denied');
      return;
    }
    await _initLiveKitEngine();
  }

  /// Core LiveKit setup — mic permission must already be granted.
  Future<void> _initLiveKitEngine() async {
    final channel = _callId ?? channelName ??
        'call_${listenerId ?? DateTime.now().millisecondsSinceEpoch}';
    _currentChannelName = channel;

    debugPrint('UserCallController: joining room $channel');

    // Fetch token
    final tokenResult = await _livekitService.fetchToken(roomName: channel);
    if (!tokenResult.success || tokenResult.token == null || tokenResult.url == null) {
      _setError(tokenResult.error ?? 'Failed to get call token');
      _stopRingtone();
      _scheduleAutoClose();
      return;
    }

    _transitionTo(UserCallState.connecting);

    final joined = await _livekitService.connectToRoom(
      url: tokenResult.url!,
      token: tokenResult.token!,
    );

    if (joined) {
      _livekitService.room?.events.listen((event) {
        if (event is ParticipantConnectedEvent) {
          debugPrint('UserCallController: listener joined call');
          _transitionTo(UserCallState.connected);
        } else if (event is ParticipantDisconnectedEvent) {
          debugPrint('UserCallController: listener left');
          endCall(reason: 'remote_end');
        } else if (event is RoomDisconnectedEvent) {
          debugPrint('UserCallController: room disconnected ${event.reason}');
          if (_callState != UserCallState.ended && !_disposed) {
             _setError('Call disconnected');
             endCall(reason: 'network_drop');
          }
        }
      });
    }

    if (!joined) {
      _setError('Failed to join call');
      _stopRingtone();
      _scheduleAutoClose();
    } else {
      _currentChannelName = channel;
      await _persistActiveCallSession();
      _socketService.joinedChannel(
        callId: channel,
        channelName: channel,
      );

      // No-answer timeout (45 seconds)
      _noAnswerTimer = Timer(const Duration(seconds: 45), () {
        if (!_disposed &&
            _callState != UserCallState.connected &&
            _callState != UserCallState.ended) {
          _setError('No answer');
          _stopRingtone();
          Future.delayed(const Duration(seconds: 2), () {
            if (!_disposed) endCall(reason: 'remote_end');
          });
        }
      });
    }
  }

  // ── User actions ──
  void toggleMute() {
    if (_disposed || _callState == UserCallState.ended) return;
    _isMuted = !_isMuted;
    _livekitService.muteLocalAudio(_isMuted);
    notifyListeners();
  }

  /// End the call with a reason. Safe to call multiple times.
  /// Reasons: "user_end", "balance_zero", "remote_end", "network_drop".
  Future<void> endCall({String reason = 'user_end'}) async {
    // Guard: prevent duplicate execution
    if (_isCallEnding || _callState == UserCallState.ended) {
      debugPrint('[CALL] endCall() skipped – already ending or ended');
      return;
    }
    _isCallEnding = true;
    _endReason = reason;
    _endCallCompleter = Completer<void>();
    debugPrint('[CALL] End call started – reason: $reason');

    try {
      final wasConnected = _callState == UserCallState.connected;
      final durationSnapshot = _callDuration;

      // 1. Stop timer & ringtone IMMEDIATELY
      _callTimer?.cancel();
      _callTimer = null;
      _noAnswerTimer?.cancel();
      _noAnswerTimer = null;
      _stopRingtone();

      // 2. Transition state → UI shows "Call Ended"
      _transitionTo(UserCallState.ended);

      // 3. Disconnect LiveKit FIRST — stops audio instantly for both sides
      debugPrint('[CALL] Disconnecting LiveKit room');
      await _livekitService.reset();

      // 4. Notify peer via socket IMMEDIATELY
      // Use _callId (DB call ID) as the primary identifier — _currentChannelName may
      // be null if the user cancelled before Agora finished initializing.
      final socketCallId = _callId ?? _currentChannelName;
      if (listenerId != null && socketCallId != null) {
        _socketService.endCall(
          callId: socketCallId,
          otherUserId: listenerId!,
          reason: wasConnected ? 'user_ended' : 'caller_cancelled',
        );
      }
      if (_currentChannelName != null) {
        _socketService.leftChannel(channelName: _currentChannelName!);
      }

      // 5. Update backend (billing / status) — can happen in background
      debugPrint('[CALL] Updating backend billing');
      final cid = _callId ?? _currentChannelName;
      if (cid != null) {
        final status = wasConnected || durationSnapshot > 0 ? 'completed' : 'cancelled';
        if (status == 'completed') {
          final result = await _callService.endCall(
            callId: cid,
            durationSeconds: durationSnapshot,
          );
          if (result.success && result.summary != null) {
            _billingSummary = result.summary;
          }
        } else {
          await _callService.updateCallStatus(
            callId: cid,
            status: status,
            durationSeconds: durationSnapshot > 0 ? durationSnapshot : null,
          );
        }
      }

      debugPrint('[CALL] Cleanup done');
    } catch (e) {
      debugPrint('[CALL] Cleanup error: $e');
    } finally {
      await _activeCallService.clearActiveCallSession();
      // Signal that cleanup is complete
      if (!_endCallCompleter!.isCompleted) {
        _endCallCompleter!.complete();
      }
      // Notify UI one final time so it can navigate
      if (!_disposed) notifyListeners();
    }
  }

  // ── Audio ──

  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('voice/calling.mp3'));
    } catch (e) {
      debugPrint('UserCallController: ringtone error: $e');
    }
  }

  void _stopRingtone() {
    try {
      _audioPlayer.stop();
    } catch (_) {}
  }

  // ── Internals ──

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _isCallEnding) return;
      _callDuration++;

      // Countdown remaining seconds (server-provided wallet-based limit)
      if (_maxAllowedSeconds > 0) {
        _remainingSeconds = (_maxAllowedSeconds - _callDuration).clamp(0, _maxAllowedSeconds);

        // Auto-disconnect when countdown reaches 0
        if (_remainingSeconds <= 0 && !_isCallEnding) {
          debugPrint('[CALL] Countdown reached 0 – auto-ending call (wallet limit)');
          endCall(reason: 'balance_zero');
          return;
        }

        // Warning at 30 seconds remaining (for UI feedback)
        if (_remainingSeconds == 30) {
          debugPrint('[CALL] Warning: 30 seconds remaining');
        }
      }

      // Fallback: periodic balance check every 60 seconds
      // Only needed when server didn't provide maxAllowedSeconds
      if (_maxAllowedSeconds <= 0 && _callDuration % 60 == 0) {
        _checkBalanceDuringCall();
      }

      notifyListeners();
    });
  }

  Future<void> _checkBalanceDuringCall() async {
    if (_isCallEnding || _disposed || _callState != UserCallState.connected) return;
    try {
      final walletResult = await _userService.getWallet();
      if (walletResult.success && walletResult.balance <= 0) {
        debugPrint('[CALL] Balance exhausted during call – auto-ending');
        endCall(reason: 'balance_zero');
      }
    } catch (e) {
      debugPrint('[CALL] Balance check error: $e');
    }
  }

  void _setError(String msg) {
    if (_disposed) return;
    _connectionError = msg;
    _stopRingtone();
    notifyListeners();
  }

  void _scheduleAutoClose() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed) endCall(reason: 'remote_end');
    });
  }

  // ── Dispose ──

  @override
  void dispose() {
    _disposed = true;
    _callConnectedSub?.cancel();
    _callEndedSub?.cancel();
    _callRejectedSub?.cancel();
    _callBusySub?.cancel();
    _noAnswerTimer?.cancel();
    _callTimer?.cancel();
    _audioPlayer.dispose();
    if (_currentChannelName != null) {
      _socketService.leftChannel(channelName: _currentChannelName!);
    }
    super.dispose();
  }
}
