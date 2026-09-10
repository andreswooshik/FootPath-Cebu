import 'package:footpath_cebu/data/local/attendance_outbox_store.dart';
import 'package:footpath_cebu/data/local/web_attendance_outbox.dart';
import 'package:idb_shim/idb_browser.dart';

AttendanceOutboxStore createAttendanceOutbox() =>
    WebAttendanceOutbox(idbFactoryBrowser);
