import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/household_collect_sheet.dart';

/// Returns a fixed set of waste types without touching the network, so the
/// sheet can be rendered in a test. Mirrors the real response shape from
/// `waste/get-waste-types/?customer_id=…` (4 streams for a household).
class _FakeRepo extends OperatorTripRepository {
  @override
  Future<List<CustomerWasteType>> fetchCustomerWasteTypes(
    String customerId,
  ) async {
    return const [
      CustomerWasteType(id: 'wst-1', name: 'Wet Waste'),
      CustomerWasteType(id: 'wst-2', name: 'Dry Waste'),
      CustomerWasteType(id: 'wst-3', name: 'Mixed Waste'),
      CustomerWasteType(id: 'wst-4', name: 'Sanitary Waste'),
    ];
  }
}

void main() {
  // registerLazySingleton must happen BEFORE pumpWidget — the sheet resolves
  // the repo in initState, which runs during the first build.
  setUp(() {
    if (GetIt.instance.isRegistered<OperatorTripRepository>()) {
      GetIt.instance.unregister<OperatorTripRepository>();
    }
    GetIt.instance.registerLazySingleton<OperatorTripRepository>(
      () => _FakeRepo(),
    );
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HouseholdCollectSheet(
              customerId: 'CUS-1',
              customerName: 'Dhandapani M (HH-12)',
              latitude: '11.1',
              longitude: '78.6',
              assignmentId: 'TRIP-1',
            ),
          ),
        ),
      );

  testWidgets('renders a card for every waste type without layout errors',
      (tester) async {
    await tester.pumpWidget(host());
    // Let the waste-type future resolve.
    await tester.pumpAndSettle();

    // The original bug: the grid threw "BoxConstraints forces an infinite
    // height" from AnimatedSize inside a stretched Row, so nothing rendered.
    expect(tester.takeException(), isNull);

    for (final name in const [
      'Wet Waste',
      'Dry Waste',
      'Mixed Waste',
      'Sanitary Waste',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '$name card missing');
    }
  });

  testWidgets('tapping a card expands it into a weight field', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wet Waste'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The expanded card owns the only text field in the sheet.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders cleanly with an odd number of waste types',
      (tester) async {
    // 3 types means the last row has a single card — the branch that used to
    // stretch a lone card across the full row.
    GetIt.instance.unregister<OperatorTripRepository>();
    GetIt.instance.registerLazySingleton<OperatorTripRepository>(
      () => _OddRepo(),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mixed Waste'), findsOneWidget);
  });
}

class _OddRepo extends OperatorTripRepository {
  @override
  Future<List<CustomerWasteType>> fetchCustomerWasteTypes(String id) async {
    return const [
      CustomerWasteType(id: 'wst-1', name: 'Wet Waste'),
      CustomerWasteType(id: 'wst-2', name: 'Dry Waste'),
      CustomerWasteType(id: 'wst-3', name: 'Mixed Waste'),
    ];
  }
}
