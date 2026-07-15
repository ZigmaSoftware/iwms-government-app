import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:iwms_citizen_app/core/env.dart';

// This function creates and configures a Dio instance
Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10), // Increased timeout
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // You can add interceptors here for logging or auth tokens
  if (!kReleaseMode) {
    dio.interceptors.add(
      LogInterceptor(responseBody: true, requestBody: true),
    );
  }

  return dio;
}

class ApiConfig {
  /// Desktop endpoints (open lists) used for driver-side data pulls.
  static const String desktopBase = kDesktopBase;
  static const bool legacyRoleAssignEnabled = false;
  static const bool legacyTripAssignEnabled = false;
  static const String wasteSummaryEndpoint =
      '${desktopBase}waste/citizen-summary/';
  static const String customerList =
      '${desktopBase}customer-masters/customercreations/';

  // --- Grievance: citizen mobile (self-scoped, auth-only) ---
  static const String citizenGrievanceTickets =
      '${desktopBase}citizen/grievance-tickets/';
  static const String citizenGrievanceMeta =
      '${desktopBase}citizen/grievance-tickets/meta/';
  // --- Grievance: supervisor / staff (department-scoped) ---
  static const String grievanceTickets = '${desktopBase}grievance/tickets/';

  static const String assignments =
      '${desktopBase}schedule-masters/daily-trip-assignments/';
  static const String staffAssignments =
      '${desktopBase}schedule-masters/daily-trip-assignments/';
  static const String collectionLogs =
      '${desktopBase}schedule-masters/bin-collection-events/';
  static const String assignmentCustomerStatuses =
      '${desktopBase}schedule-masters/daily-trip-household-collections/';
  static const String citizenAssignments =
      '${desktopBase}schedule-masters/daily-trip-household-collections/';
  static const String tripAssignments =
      '${desktopBase}schedule-masters/daily-trip-assignments/';
  static const String tripShifts = '${desktopBase}schedule-masters/trip-plans/';
  static const String tripCollectionPoints =
      '${desktopBase}schedule-masters/daily-trip-collection-points/';
  static const String tripRoutePlans =
      '${desktopBase}schedule-masters/trip-plans/';
  static const String tripPlannedStops =
      '${desktopBase}schedule-masters/trip-plan-collection-points/';
  static const String tripRouteGeometry =
      '${desktopBase}schedule-masters/daily-trip-collection-points/tracking/';
  static const String tripExecutionStops =
      '${desktopBase}schedule-masters/daily-trip-collection-points/';
  static const String tripRoutePlanGenerate =
      '${desktopBase}schedule-masters/daily-trip-collection-points/optimize-route/';
  static const String tripGenerate =
      '${desktopBase}schedule-masters/daily-trip-assignments/generate-daily/';
  static const String tripDriverRoute =
      '${desktopBase}schedule-masters/daily-trip-collection-points/tracking/';
  static const String staffTemplates =
      '${desktopBase}schedule-masters/staff-templates/';
  static const String vehicles =
      '${desktopBase}transport-masters/vehicle-creation/';
  static const String users = '${desktopBase}user-creations/users-creation/';
  static const String subproperties =
      '${desktopBase}waste-types/subproperties/';
  static const String wards = '${desktopBase}masters/panchayat/';
  static const String zones = '${desktopBase}masters/hierarchy-nodes/';

  // Operator-mobile flow
  static const String operatorMyTripToday =
      '${desktopBase}operator-mobile/my-trip-today/';
  static const String operatorValidateBinQr =
      '${desktopBase}operator-mobile/validate-bin-qr/';
  static const String operatorScanBin =
      '${desktopBase}operator-mobile/scan-bin/';
  static const String operatorTripHistory =
      '${desktopBase}operator-mobile/trip-history/';

  // ORS key is sourced from build-time env (`VITE_ORS_API_KEY`).
  static const String orsApiKey = kOrsApiKey;

  static const String driverNextHouse = '$kApiBase/driver/next-house/';
  static const String updateAssignmentStatus =
      '$kApiBase/driver/assignment/update-status/';

  /// Government Django backend endpoint for mobile authentication.
  /// Login is exposed at `/api/v1/login/`.
  static const String _defaultMobileLogin = '${desktopBase}login/';
  static const String _defaultCitizenLogin = _defaultMobileLogin;
  static const String citizenLogin = String.fromEnvironment(
    'CITIZEN_LOGIN_URL',
    defaultValue: _defaultCitizenLogin,
  );
  // Mobile apps should use the unified mobile login endpoint.
  static const String staffLogin = _defaultMobileLogin;
  static const String mobileLogin = _defaultMobileLogin;
  static const String myPermissions = '${desktopBase}login/my-permissions/';

  /// Default user type identifier expected by the Django login API.
  static const String citizenUserType = 'citizen';
}
