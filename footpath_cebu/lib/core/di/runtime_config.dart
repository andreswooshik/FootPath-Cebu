import 'package:flutter/foundation.dart' show kReleaseMode;

import 'test_runtime_stub.dart' if (dart.library.io) 'test_runtime_io.dart';

const bool mockDataRequestedByBuild = bool.fromEnvironment(
  'USE_MOCK',
  defaultValue: false,
);

bool get useMockData {
  if (kReleaseMode) return false;
  if (isFlutterTestRuntime) return true;
  return mockDataRequestedByBuild;
}
