import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/services/ble_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'iOS defers authorization to CoreBluetooth without a permission channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // No permission-handler method channel is registered in this test.
      await requestScooterPermissions();
    },
  );

  test(
    'unsupported desktop platforms reject Bluetooth controls clearly',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await expectLater(requestScooterPermissions(), throwsStateError);
    },
  );
}
