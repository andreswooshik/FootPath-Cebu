import 'package:footpath_cebu/domain/repositories/device_repository.dart';

/// No-op device registration for UI development without Firebase/FCM.
class MockDeviceRepository implements DeviceRepository {
  @override
  Future<void> registerCurrentDevice() async {}

  @override
  Future<void> unregisterCurrentDevice() async {}
}
