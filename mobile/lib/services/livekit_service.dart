import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'api_service.dart';
import 'api_config.dart';

class TokenResult {
  final bool success;
  final String? token;
  final String? url;
  final String? error;

  TokenResult({
    required this.success,
    this.token,
    this.url,
    this.error,
  });
}

class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;
  LiveKitService._internal();

  Room? _room;
  bool _isInRoom = false;
  String? _currentRoomName;

  bool get isInRoom => _isInRoom;
  String? get currentRoomName => _currentRoomName;

  /// Fetch token from backend
  Future<TokenResult> fetchToken({required String roomName}) async {
    try {
      debugPrint('LiveKitService: Fetching token for room: $roomName');
      
      final apiService = ApiService();
      // The backend should return LiveKit tokens now instead of Agora
      final response = await apiService.post(
        ApiConfig.livekitToken,
        body: {
          'channel_name': roomName,
        },
      );

      if (response.isSuccess) {
        final data = response.data;
        debugPrint('LiveKitService: Token fetched successfully');
        return TokenResult(
          success: true,
          token: data['token'],
          // Provide default URL if backend doesn't return one
          url: data['url'] ?? 'wss://livekit.appdost.com',
        );
      } else {
        return TokenResult(
          success: false,
          error: response.error ?? 'Failed to get token',
        );
      }
    } catch (e) {
      debugPrint('LiveKitService: Token fetch error: $e');
      return TokenResult(
        success: false,
        error: 'Network error: $e',
      );
    }
  }

  Room? get room => _room;

  Future<bool> connectToRoom({
    required String url,
    required String token,
  }) async {
    if (_isInRoom) {
      debugPrint('LiveKitService: Already in room, leaving first...');
      await disconnect();
    }

    try {
      debugPrint('LiveKitService: Connecting to LiveKit room...');
      _room = Room();

      await _room!.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // AUDIO-ONLY: Enable Local Microphone
      await _room!.localParticipant?.setMicrophoneEnabled(true);

      _isInRoom = true;
      _currentRoomName = _room!.name;
      debugPrint('LiveKitService: Connected to room: $_currentRoomName');
      return true;
    } catch (e) {
      debugPrint('LiveKitService: Failed to connect to room - $e');
      return false;
    }
  }

  Future<void> muteLocalAudio(bool mute) async {
    try {
      if (_room?.localParticipant != null) {
        debugPrint('LiveKitService: ${mute ? "Muting" : "Unmuting"} local audio');
        await _room!.localParticipant!.setMicrophoneEnabled(!mute);
      }
    } catch (e) {
      debugPrint('LiveKitService: Failed to mute local audio - $e');
    }
  }

  Future<void> disconnect() async {
    try {
      if (_room != null) {
        debugPrint('LiveKitService: Disconnecting from room');
        await _room!.disconnect();
        _room!.dispose();
        _room = null;
      }
      _isInRoom = false;
      _currentRoomName = null;
    } catch (e) {
      debugPrint('LiveKitService: Failed to disconnect - $e');
    }
  }

  Future<void> reset() async {
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
