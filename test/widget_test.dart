import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/widgets.dart';

void main() {
  testWidgets('ErrorView muestra el mensaje y llama a reintentar', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: ErrorView(message: 'Sin conexión', onRetry: () => retried = true)),
    ));
    expect(find.text('Sin conexión'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });
}
