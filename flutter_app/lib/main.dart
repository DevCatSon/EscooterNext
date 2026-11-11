import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'catalog/scooter_catalog.dart';
import 'services/ble_transport.dart';
import 'services/preferences.dart';
import 'services/scooter_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Escooter Next',
    ], await rootBundle.loadString('LICENSE'));
  });
  final preferences = LocalPreferenceStore(
    await SharedPreferences.getInstance(),
  );
  final controller = ScooterController(
    transport: ReactiveScooterTransport(),
    preferences: preferences,
    catalog: ScooterCatalog.fromJson(
      await rootBundle.loadString('assets/scooter_catalog.json'),
    ),
  );
  runApp(ScooterApp(controller: controller, disposeController: true));
}
