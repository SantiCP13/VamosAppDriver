import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  static Future<String> getId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      // .id es el identificador único de la placa base/hardware en Android
      return androidInfo.id;
    } else {
      var iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    }
  }

  static Future<String> getName() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      return "${androidInfo.manufacturer} ${androidInfo.model}";
    } else {
      var iosInfo = await deviceInfo.iosInfo;
      return iosInfo.name;
    }
  }
}
