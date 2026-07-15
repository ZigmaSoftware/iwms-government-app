import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode/print

// Layered imports
import '../models/vehicle_model.dart';
import '../../core/api_config.dart';
import '../../core/network/authorized_dio.dart';

class VehicleRepository {
  final Dio dioClient;

  VehicleRepository({
    required this.dioClient,
  });

  // Fetch vehicle positions from the government backend.
  Future<List<VehicleModel>> fetchAllVehicleLocations() async {
    try {
      final dio = await authorizedDio();
      final Response response = await dio.get(
        '${ApiConfig.tripCollectionPoints}tracking-overview/',
      );

      if (response.statusCode == 200 && response.data != null) {
        final decoded = response.data;
        final List<dynamic> dataList = decoded is List
            ? decoded
            : (decoded is Map
                ? (decoded['trips'] as List? ?? const [])
                : const []);

        return dataList
            .map((json) => _vehicleFromGovernmentTrip(
                  Map<String, dynamic>.from(json as Map),
                ))
            .where((vehicle) => vehicle.latitude != 0 || vehicle.longitude != 0)
            .toList();
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: "API returned status code: ${response.statusCode}",
        );
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        print('Network Error fetching vehicles: ${e.message}');
      }
      throw Exception("Network Error: Could not connect to API.");
    } catch (e) {
      if (kDebugMode) {
        print('Parsing/Format Error: $e');
      }
      throw Exception(
          "Failed to process vehicle data. Check model keys and API format.");
    }
  }

  VehicleModel _vehicleFromGovernmentTrip(Map<String, dynamic> json) {
    final vehicleStart = json['vehicle_start'];
    double latitude = 0;
    double longitude = 0;
    if (vehicleStart is List && vehicleStart.length >= 2) {
      longitude = _parseDouble(vehicleStart[0]);
      latitude = _parseDouble(vehicleStart[1]);
    }

    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};

    return VehicleModel(
      id: json['assignment_id']?.toString() ??
          json['vehicle_no']?.toString() ??
          '${latitude}_$longitude',
      latitude: latitude,
      longitude: longitude,
      registrationNumber: json['vehicle_no']?.toString(),
      status: json['status']?.toString(),
      lastUpdated: json['trip_date']?.toString(),
      address: 'Government trip assignment',
      distanceKm: _parseDouble(json['distance_meters']) / 1000,
      wasteCapacityKg: _parseDouble(summary['total']),
    );
  }

  double _parseDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
