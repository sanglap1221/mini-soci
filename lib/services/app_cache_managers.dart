import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Provides shared cache manager instances for the application.
class AppCacheManagers {
  AppCacheManagers._();

  // The cache object limits approximate ~100 MB when average image sizes are ~256 KB.
  static final CacheManager imageCache = CacheManager(
    Config(
      'appImageCache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 400,
      repo: JsonCacheInfoRepository(databaseName: 'appImageCache'),
      fileService: HttpFileService(),
    ),
  );

  static final CacheManager apiCache = CacheManager(
    Config(
      'apiResponseCache',
      stalePeriod: const Duration(minutes: 10),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'apiResponseCache'),
      fileService: HttpFileService(),
    ),
  );
}
