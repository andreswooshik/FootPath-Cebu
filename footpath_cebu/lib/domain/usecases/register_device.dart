import 'package:footpath_cebu/domain/repositories/device_repository.dart';

/// Use case: register the current device for push notifications after login.
class RegisterDevice {
  const RegisterDevice(this._repository);

  final DeviceRepository _repository;

  Future<void> call() => _repository.registerCurrentDevice();
}
