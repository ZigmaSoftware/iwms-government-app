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
  // Attendance module (face registration/recognition, daily register,
  // staff profile) was moved under this prefix on the government backend.
  static const String attendanceBase = '${desktopBase}attendance/';
  static const bool legacyRoleAssignEnabled = false;
  static const bool legacyTripAssignEnabled = false;
  static const String wasteSummaryEndpoint =
      '${desktopBase}waste/citizen-summary/';
  // NOTE: government backend does not yet implement this action (household
  // collection viewset is plain CRUD). Path mirrors iwms-app for consistency;
  // needs a matching endpoint on iwms-government-backend before it works at runtime.
  static const String householdCollectionMarkStatus =
      '${desktopBase}waste/mark-household-status/';
  static const String customerList =
      '${desktopBase}customer-masters/customercreations/';
  static const String registerFcmToken =
      '${desktopBase}customer-masters/customercreations/register-fcm-token/';

  // --- Grievance / complaint: citizen mobile (self-scoped, auth-only) ---
  // Government backend exposes the citizen complaint API under `citizen/complaint-tickets/`
  // (list / create / {id} / meta) — same request+response contract as the old
  // `citizen/grievance-tickets/` routes.
  static const String citizenGrievanceTickets =
      '${desktopBase}citizen/complaint-tickets/';
  static const String citizenGrievanceMeta =
      '${desktopBase}citizen/complaint-tickets/meta/';
  // --- Grievance / complaint: supervisor / staff (team + department scoped) ---
  // `complaint-ticket/tickets/` supports {id}/status/, {id}/escalate/, {id}/resolve/
  // actions matching the supervisor repository's calls.
  static const String grievanceTickets =
      '${desktopBase}complaint-ticket/tickets/';

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
  // All of the operator's trips today (bin + household + bulk) for the header
  // carousel.
  static const String operatorMyTripsToday =
      '${desktopBase}operator-mobile/my-trips-today/';
  static const String operatorValidateBinQr =
      '${desktopBase}operator-mobile/validate-bin-qr/';
  static const String operatorScanBin =
      '${desktopBase}operator-mobile/scan-bin/';
  static const String operatorTripHistory =
      '${desktopBase}operator-mobile/trip-history/';

  // ORS key is sourced from build-time env (`VITE_ORS_API_KEY`).
  static const String orsApiKey = kOrsApiKey;

  // Live GPS feed used by all-vehicle map screens. Route/trip maps still use
  // the government backend; this endpoint provides actual vehicle telemetry.
  static const String vehicleLiveApi =
      '$kVehicleLiveApiBaseUrl?providerName=$kVehicleProviderName&fcode=$kVehicleFCode';

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
