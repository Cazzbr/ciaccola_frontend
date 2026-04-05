import 'package:sqflite_common/sqlite_api.dart';
import 'database_factory_io.dart'
    if (dart.library.html) 'database_factory_web.dart';

DatabaseFactory get databaseFactory => databaseFactoryImpl;
