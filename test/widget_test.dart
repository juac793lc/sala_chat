// Test básico para la aplicación Sala Chat
//
// Verifica que la aplicación se construya correctamente y muestre
// las pantallas principales sin errores.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sala_chat/main.dart';

void main() {
  testWidgets('SalaChatApp se construye correctamente', (WidgetTester tester) async {
    // Construir la aplicación y renderizar un frame
    await tester.pumpWidget(const SalaChatApp());

    // Verificar que la aplicación se carga (debería mostrar "Cargando..." o la pantalla de bienvenida)
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Verificar que hay un Scaffold (estructura básica de la app)
    expect(find.byType(Scaffold), findsOneWidget);
    
    // Verificar que se muestra algún contenido (texto "Cargando..." o elementos de bienvenida)
    final loadingText = find.text('Cargando...');
    final welcomeElements = find.byType(CircularProgressIndicator);
    
    // Al menos uno de estos debería existir
    expect(loadingText.evaluate().isNotEmpty || welcomeElements.evaluate().isNotEmpty, isTrue);
  });

  testWidgets('Aplicación tiene título correcto', (WidgetTester tester) async {
    await tester.pumpWidget(const SalaChatApp());
    
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, equals('Sala Chat'));
  });
}
