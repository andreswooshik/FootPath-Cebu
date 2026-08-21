/// Registers the current device for push notifications.
///
/// The concrete implementation obtains the platform push token (FCM) and sends
/// it to the backend so the server can fan out notifications to this device.
abstract class DeviceRepository {
  /// Requests notification permission (if needed), obtains the push token, and
  /// registers it with the backend. Best-effort: implementations should not
  /// throw into the login flow — a device that can't register still uses the
  /// app, just without push.
  Future<void> registerCurrentDevice();

  /// Removes this device token from the signed-in user's backend registrations.
  /// Best-effort so notification cleanup can never prevent sign-out.
  Future<void> unregisterCurrentDevice();
}
