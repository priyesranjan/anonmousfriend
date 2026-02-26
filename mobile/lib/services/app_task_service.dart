import 'package:flutter/services.dart';

/// Android task controls used by the in-call UI.
class AppTaskService {
  static const MethodChannel _channel = MethodChannel('com.callto.app/app_task');

  static final AppTaskService _instance = AppTaskService._internal();
  factory AppTaskService() => _instance;
  AppTaskService._internal();

  Future<bool> moveToBack() async {
    try {
      final moved = await _channel.invokeMethod<bool>('moveToBack');
      return moved ?? false;
    } catch (_) {
      return false;
    }
  }
}
