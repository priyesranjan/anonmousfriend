import 'dart:async';
import 'package:flutter/services.dart';

/// Bridge for Android foreground service notifications during active calls.
class CallForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'com.callto.app/call_foreground_service',
  );

  static final CallForegroundService _instance = CallForegroundService._internal();
  factory CallForegroundService() => _instance;
  CallForegroundService._internal() {
    _registerHandler();
  }

  final StreamController<void> _openCallScreenController =
      StreamController<void>.broadcast();
  bool _handlerRegistered = false;

  Stream<void> get onOpenCallScreen => _openCallScreenController.stream;

  void _registerHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openCallScreen') {
        _openCallScreenController.add(null);
      }
    });
  }

  Future<void> start({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod('startService', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  Future<void> update({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod('updateService', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (_) {}
  }
}
