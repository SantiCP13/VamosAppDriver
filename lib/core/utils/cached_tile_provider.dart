import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CachedTileProvider extends TileProvider {
  static final customCacheManager = CacheManager(
    Config(
      'mapboxTilesCache_driver',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 5000,
    ),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);

    // LLAVE ESTÁTICA SIN TOKEN
    final String staticCacheKey = url.split('?').first;

    return CachedNetworkImageProvider(
      url,
      cacheManager: customCacheManager,
      cacheKey: staticCacheKey,
      headers: const {'User-Agent': 'com.vamosapp.vamosdriver'},
    );
  }
}
