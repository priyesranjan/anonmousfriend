import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'socket_service.dart';
import 'storage_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'callto_foreground', // id
    'CallTo Background Service', // name
    description: 'Keeps the app connected to receive calls', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'callto_foreground',
      initialNotificationTitle: 'CallTo is running',
      initialNotificationContent: 'Listening for incoming calls',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  final isListener = await storage.getIsListener();
  
  if (!isListener) {
    debugPrint('[BackgroundService] User is not a listener. Stopping service.');
    service.stopSelf();
    return;
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Create high importance channel for ringing
  const AndroidNotificationChannel ringingChannel = AndroidNotificationChannel(
    'callto_ringing', // id
    'Incoming Calls', // name
    description: 'Notifications for incoming calls',
    importance: Importance.max,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(ringingChannel);

  // If this is an Android device, we can update the notification text dynamically
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Initialize a background socket connection
  final socketService = SocketService();
  
  // We don't want to interfere if the app is actually in foreground, 
  // but if the isolate runs, it implies it's detached from the main UI thread.
  // Connect cleanly here:
  await socketService.connect();

  socketService.onIncomingCall.listen((call) {
    debugPrint('[BackgroundService] Incoming call received: ${call.callId}');
    
    // Trigger high-priority Heads-up Notification
    flutterLocalNotificationsPlugin.show(
      call.callId.hashCode,
      'Incoming Call 📞',
      '${call.callerName} is calling you on CallTo',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'callto_ringing',
          'Incoming Calls',
          channelDescription: 'Notifications for incoming calls',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          ongoing: true,
        ),
      ),
      payload: call.callId,
    );
  });
}
