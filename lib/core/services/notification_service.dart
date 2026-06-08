import 'dart:typed_data'; // 🟢 REQUERIDO PARA LOS PATRONES DE VIBRACIÓN Y BANDERAS NATIVAS
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Inicializa el sistema de notificaciones locales de Android e iOS
  static Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  /// Método para disparar una notificación de inmediato que repite el sonido nativo
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final Int64List vibrationPattern = Int64List.fromList([
      0,
      2000,
      1000,
      2000,
      1000,
      2000,
      1000,
      2000,
      1000,
      2000,
    ]);

    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'break_alarm_channel_heavy',
      'Alarma de Descansos Potente',
      channelDescription: 'Canal de alta prioridad para fin de descansos',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,

      // 🟢 SOLUCIÓN: Agregamos la bandera nativa FLAG_INSISTENT (valor 4) usando additionalFlags
      additionalFlags: Int32List.fromList(<int>[4]),

      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      ongoing: true, // Evita que se descarte barriendo
      vibrationPattern: vibrationPattern,
      enableVibration: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, platformDetails);
  }

  /// Programa una alarma pesada que repetirá el sonido del usuario en el futuro
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required Duration delay,
  }) async {
    final Int64List vibrationPattern = Int64List.fromList([
      0,
      2000,
      1000,
      2000,
      1000,
      2000,
      1000,
      2000,
      1000,
      2000,
    ]);

    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'break_alarm_channel_heavy_scheduled',
      'Alarma de Descansos Programada Potente',
      channelDescription:
          'Canal de alta potencia para fin de descansos en segundo plano',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,

      // 🟢 SOLUCIÓN: Agregamos la bandera nativa FLAG_INSISTENT (valor 4) usando additionalFlags
      additionalFlags: Int32List.fromList(<int>[4]),

      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      vibrationPattern: vibrationPattern,
      enableVibration: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.now(tz.local).add(delay),
      platformDetails,
      androidScheduleMode:
          AndroidScheduleMode.exactAllowWhileIdle, // Suena en reposo profundo
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancela la alarma del break apagando el bucle de sonido nativo
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
