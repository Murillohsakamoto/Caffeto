// Roteiro que abre o app no simulador de iPhone e tira os prints da App Store.
// Roda no Codemagic (workflow "iOS - Prints da loja").
// A conta de teste vem de variáveis secretas: TEST_EMAIL e TEST_PASSWORD.
import 'dart:async';

import 'package:caffeto/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _senha = String.fromEnvironment('TEST_PASSWORD');

/// Avança a tela por alguns segundos (carregamentos de rede e animações).
Future<void> _esperar(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Espera até [finder] aparecer (no máximo [segundos]).
Future<void> _esperarAparecer(WidgetTester tester, Finder finder,
    {int segundos = 30}) async {
  for (var i = 0; i < segundos * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Não apareceu na tela: $finder');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prints da App Store', (tester) async {
    expect(_email.isNotEmpty && _senha.isNotEmpty, isTrue,
        reason: 'Defina TEST_EMAIL e TEST_PASSWORD no Codemagic.');

    // Erros de carregamento em segundo plano (ex.: Firestore oscilando no
    // simulador) não devem derrubar o roteiro: o app já trata isso na tela.
    final tratadorOriginal = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      debugPrint('Ignorado durante os prints: ${detalhes.exceptionAsString()}');
    };
    runZonedGuarded(app.main, (erro, _) {
      debugPrint('Ignorado durante os prints: $erro');
    });
    try {
      await _esperarAparecer(tester, find.text('Bem-vindo de volta!'));
      await _esperar(tester, 2);

      // 1. Tela de login
      await binding.takeScreenshot('01_login');

      // Entra com a conta de teste
      await tester.enterText(find.byType(TextField).at(0), _email);
      await tester.enterText(find.byType(TextField).at(1), _senha);
      FocusManager.instance.primaryFocus?.unfocus();
      await _esperar(tester, 1);
      await tester.tap(find.text('Entrar'));

      // 2. Início
      await _esperarAparecer(tester, find.byIcon(Icons.home));
      await _esperar(tester, 6);
      await binding.takeScreenshot('02_inicio');

      // 3. Cardápio
      await tester.tap(find.byIcon(Icons.restaurant_menu_outlined));
      await _esperar(tester, 6);
      await binding.takeScreenshot('03_cardapio');

      // 4. Sacola com um item
      final adicionar = find.byIcon(Icons.add);
      if (adicionar.evaluate().isNotEmpty) {
        await tester.tap(adicionar.first);
        await _esperar(tester, 5); // deixa o aviso "adicionado" sumir
      }
      await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
      await _esperar(tester, 3);
      await binding.takeScreenshot('04_sacola');

      // 5. Perfil
      await tester.tap(find.byIcon(Icons.person_outline));
      await _esperar(tester, 4);
      await binding.takeScreenshot('05_perfil');
      await _esperar(tester, 1);
    } finally {
      FlutterError.onError = tratadorOriginal;
    }
  });
}
