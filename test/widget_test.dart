// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. To use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:mi_primer_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Usamos ParkinsonApp que es el nombre real del widget raíz en main.dart
    await tester.pumpWidget(const ParkinsonApp());

    // Este test es básico para verificar que la app carga sin explotar.
    // Dado que la app inicia con Firebase y StreamBuilder, el contenido dependerá del estado de auth.
    expect(find.byType(ParkinsonApp), findsOneWidget);
  });
}
