import 'package:footpath_cebu/domain/repositories/device_repository.dart';

/// Best-effort removal of the current FCM token before authentication ends.
class UnregisterDevice {
  const UnregisterDevice(this._repository);

  final DeviceRepository _repository;

  Future<void> call() => _repository.unregisterCurrentDevice();
}
