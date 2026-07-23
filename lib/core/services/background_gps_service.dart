import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundGpsService {
  /// Inicializa las configuraciones globales del servicio
  static void init() {
    FlutterForegroundTask.init(
      // 🟢 CORREGIDO: Removido 'const' de AndroidNotificationOptions
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'vamos_driver_tracking_channel',
        channelName: 'Servicio de Conducción Activo',
        channelDescription:
            'Mantiene el GPS activo durante tus viajes en curso.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      // 🟢 CORREGIDO: Removido 'const' de ForegroundTaskOptions
      foregroundTaskOptions: ForegroundTaskOptions(
        // 🟢 CORREGIDO: Se pasa el entero 5000 directamente en lugar de un objeto Duration
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Enciende el servicio nativo de segundo plano
  static Future<void> start({
    required String title,
    required String message,
  }) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        // Si ya está corriendo, solo actualizamos el texto de la notificación
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: message,
        );
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: message,
      );
      debugPrint("🛰️ [FOREGROUND SERVICE] Iniciado con éxito.");
    } catch (e) {
      debugPrint("🚨 [FOREGROUND SERVICE] Error al iniciar: $e");
    }
  }

  /// Apaga el servicio y libera la batería del teléfono
  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        debugPrint("🔌 [FOREGROUND SERVICE] Detenido de forma segura.");
      }
    } catch (e) {
      debugPrint("🚨 [FOREGROUND SERVICE] Error al detener: $e");
    }
  }
}
