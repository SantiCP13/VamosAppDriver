import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CachedTileProvider extends TileProvider {
  static final customCacheManager = CacheManager(
    Config(
      'vamosTilesCache', // Nombre de caché limpio
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 15000,
      fileService:
          AggressiveHttpFileService(), // Se activa el servicio de caché de 30 días
    ),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);

    // Clave única basada en la ruta de la tesela
    final uri = Uri.parse(url);
    final String cleanKey = "${uri.host}${uri.path}";

    return CachedNetworkImageProvider(
      url,
      cacheManager: customCacheManager,
      cacheKey: cleanKey,
      headers: const {
        'User-Agent': 'com.vamosapp.vamosplatform',
        'Accept': 'image/webp,image/*;q=0.8',
      },

      // 🟢 ESCUDO CONTRA CRASHEOS DE RED:
      // Captura timeouts, caídas de señal y DNS caídos de forma segura sin cerrar la App
      errorListener: (Object exception) {
        debugPrint(
          "⚠️ [MAP ERROR CATCH] No se pudo descargar la tesela en ${coordinates.z}/${coordinates.x}/${coordinates.y}: $exception",
        );
      },
    );
  }
}

/// Servicio de red que sobreescribe la validez de las imágenes descargadas (Para CartoDB)
class AggressiveHttpFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    debugPrint(
      "🌐 [TILE NETWORK HIT] Descargando mapa desde internet: ${url.split('?').first}",
    );
    final response = await super.get(url, headers: headers);
    return ForcedCacheFileResponse(response);
  }
}

/// Adaptador que delega las propiedades originales e implementa los getters requeridos
class ForcedCacheFileResponse implements FileServiceResponse {
  final FileServiceResponse _originalResponse;

  ForcedCacheFileResponse(this._originalResponse);

  @override
  Stream<List<int>> get content => _originalResponse.content;

  @override
  int? get contentLength => _originalResponse.contentLength;

  @override
  String get fileExtension => _originalResponse.fileExtension;

  @override
  int get statusCode => _originalResponse.statusCode;

  @override
  String? get eTag => _originalResponse.eTag;

  @override
  DateTime get validTill {
    // Retorna una vigencia fija de 30 días para evitar descargas duplicadas
    return DateTime.now().add(const Duration(days: 30));
  }
}
