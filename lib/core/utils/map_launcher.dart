import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';

class MapLauncher {
  static Future<void> launchNavigation({
    required LatLng destination,
    String? label,
  }) async {
    final lat = destination.latitude;
    final lng = destination.longitude;

    // Intentamos abrir Waze primero (url scheme), si no, Google Maps
    final Uri wazeUri = Uri.parse("waze://?ll=$lat,$lng&navigate=yes");
    final Uri googleMapsUri = Uri.parse("google.navigation:q=$lat,$lng");

    // Fallback para iOS o web
    final Uri webUri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng",
    );

    try {
      if (await canLaunchUrl(wazeUri)) {
        await launchUrl(wazeUri);
      } else if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Si todo falla, abrimos el navegador
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }
}
