import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/screens/login_screen.dart';
import 'package:mobile/services/hotel_store.dart';

void main() {
  testWidgets('EaseInn login flow and dashboard launch smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = HotelStore();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Initial state: Login screen is displayed
    expect(find.text('EaseInn PMS'), findsOneWidget);
    expect(find.text('Sign In to Shift'), findsNWidgets(2));
    expect(find.text('Quick Demo Login (Devika Rao)'), findsOneWidget);

    // Tap Quick Demo Login
    await tester.ensureVisible(find.text('Quick Demo Login (Devika Rao)'));
    await tester.tap(find.text('Quick Demo Login (Devika Rao)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Now authenticated: HomeShell and Dashboard are displayed
    expect(store.isAuthenticated, isTrue);
    expect(find.text('EaseInn Boutique & Suites'), findsWidgets);
    expect(find.textContaining('Devika'), findsWidgets);

    // Real dynamic KPI metrics are displayed
    expect(find.text('Arrivals'), findsOneWidget);
    expect(find.text('Departures'), findsOneWidget);
    expect(find.text('Occupancy'), findsOneWidget);
    expect(find.text('Room Status'), findsOneWidget);
    expect(find.text("Today's Collection"), findsOneWidget);

    // Bottom navigation bar labels exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Guests'), findsOneWidget);

    // Switch to Rooms tab by tapping label
    await tester.tap(find.text('Rooms'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify room view loaded
    expect(find.text('Rooms & Floors'), findsOneWidget);
  });
}
