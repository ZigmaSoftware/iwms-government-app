import 'package:dio/dio.dart';
import 'package:iwms_citizen_app/core/geofence_config.dart';
import '../models/site_polygon.dart';

class SiteRepository {
  final Dio dioClient;
  SiteRepository({required this.dioClient});

  Future<List<SitePolygon>> fetchSites() async {
    return <SitePolygon>[
      SitePolygon(
        name: GammaGeofenceConfig.name,
        points: GammaGeofenceConfig.polygon,
      ),
    ];
  }
}
