import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

DatabaseFactory get databaseFactoryImpl {
  if (!_initialized) {
    sqfliteFfiInit();
    _initialized = true;
  }
  return databaseFactoryFfi;
}
