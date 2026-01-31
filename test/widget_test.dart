import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troonky_link/main.dart'; // RootApp is here

void main() {
  testWidgets(
    'App loads splash screen and navigates forward',
        (WidgetTester tester) async {

      // 1️⃣ Load app (Root widget)
      await tester.pumpWidget(const RootApp());

      // 2️⃣ Splash screen indicator should be visible first
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 3️⃣ Let splash timer & navigation finish
      await tester.pumpAndSettle();

      // 4️⃣ App should NOT crash
      // Either Login page OR Main app loads depending on auth state
      expect(
        find.byType(Scaffold),
        findsWidgets,
      );
    },
  );
}
