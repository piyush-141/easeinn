import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/hotel_store.dart';

void main() {
  testWidgets('EaseInn login flow and dashboard launch smoke test', (WidgetTester tester) async {
    final store = HotelStore();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const EaseInnApp(),
      ),
    );

    // Initial state: Login screen is displayed
    expect(find.text('EaseInn PMS'), findsOneWidget);
    expect(find.text('Staff Login'), findsOneWidget);
    expect(find.text('Quick Demo Login (Devika Rao)'), findsOneWidget);

    // Tap Quick Demo Login
    await tester.tap(find.text('Quick Demo Login (Devika Rao)'));
    await tester.pumpAndSettle();

    // Now authenticated: HomeShell and Dashboard are displayed
    expect(store.isAuthenticated, isTrue);
    expect(find.text('EaseInn Boutique & Suites'), findsOneWidget);
    expect(find.text('Logged in as Devika Rao (Front Desk Lead)'), findsOneWidget);

    // Real dynamic KPI metrics are displayed
    expect(find.text('Occupied'), findsOneWidget);
    expect(find.text('Vacant'), findsOneWidget);
    expect(find.text('Needs Cleaning'), findsOneWidget);
    expect(find.text('Today Collected'), findsOneWidget);
    expect(find.text('New Check-In (Aadhaar OCR)'), findsOneWidget);

    // Bottom navigation bar labels exist
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Check-Out'), findsNWidgets(2)); // Quick action card + bottom nav
    expect(find.text('Guests'), findsOneWidget);

    // Switch to Rooms tab by tapping label
    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();

    // Verify room view loaded
    expect(find.text('Rooms & Housekeeping'), findsOneWidget);
  });
}
