// ignore_for_file: avoid_print, deprecated_member_use

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
String? numeroVinculado;
Telephony? telephony;
bool escuchando = false;

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
  DartPluginRegistrant.ensureInitialized();
  telephony = Telephony.instance;
  bool automatico = false;
  Timer? t;
  int intervaloEnvio = 60;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  service.on('setNumber').listen((event) {
    numeroVinculado = event?['numero'] as String?;
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('listenSMS').listen((event) {
    escuchando = true;
  });

  service.on('stoplisteningSMS').listen((event) {
    escuchando = false;
  });

  

  service.on("setInterval").listen((event) {
    if (event?["intervalo"] != null) {
      intervaloEnvio = event!["intervalo"];
    }
  });


  service.on('automatic').listen((event) {
    automatico = true;
    t = Timer.periodic(intervaloEnvio>=60? Duration(minutes: (intervaloEnvio/60).toInt()): Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService() && automatico) {
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
            print("Mensaje: $mensaje");

            await telephony!.sendSms(to: numeroVinculado!, message: mensaje);
          } catch (e) {
            print("Error enviando SMS: $e");
          }
        } else {
          timer.cancel();
          return;
        }
      }
    });
  });

  service.on('stopautomatic').listen((event) {
    automatico = false;
    if (t != null) t?.cancel();
  });
}

@pragma('vm:entry-point')
Future<void> mensajeBackground(SmsMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  // Verificamos que haya un número vinculado
  if (numeroVinculado == null || !escuchando) return;

  // Normalizamos ambos números para comparar (por si uno tiene +54 y otro no)
  final remitente = message.address?.replaceAll(RegExp(r'\D'), '');
  final vinculado = numeroVinculado?.replaceAll(RegExp(r'\D'), '');

  if (remitente == null || !remitente.endsWith(vinculado!)) return;

  // Procesamos la ubicación si viene del número vinculado
  print("MENSAJE RECIBIDO: ${message.body}");
  final partes = message.body?.split(',');
  if (partes != null && partes.length == 3 && partes[2] == "_S_U") {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final mensaje = "${pos.latitude},${pos.longitude}";
      print("Solicitud de ubicacion: $mensaje");

      await telephony!.sendSms(to: numeroVinculado!, message: mensaje);
    } catch (e) {
      print("Error enviando SMS: $e");
    }
  }
}
