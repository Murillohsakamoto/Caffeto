import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Recebe os prints tirados no simulador e salva em screenshots/<nome>.png
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = await File('screenshots/$name.png').create(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
