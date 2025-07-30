import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';

// this will be used as notification channel id
const notificationChannelId = 'location_app';

// this will be used for notification id, So you can update your custom notification with this id.
const notificationId = 888;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'LOCATION APP', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Enviando ubicación',
      initialNotificationContent: 'El servicio está activo',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );

  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  String? numeroVinculado;
  final telephony = Telephony.instance;
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  service.on('setNumber').listen((event) {
    numeroVinculado = event?['numero'] as String?;
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await flutterLocalNotificationsPlugin.show(
          notificationId,
          'LOCATION APP',
          '${DateTime.now()}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              notificationChannelId,
              'LOCATION APP',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );
        if (numeroVinculado == null) return;

        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );

          final mensaje = "${pos.latitude},${pos.longitude}";
          print("Mensaje: ${mensaje}");

          await telephony.sendSms(to: numeroVinculado!, message: mensaje);
        } catch (e) {
          print("Error enviando SMS: $e");
        }
      } else {
        timer.cancel();
        return;
      }
    }
  });
}
