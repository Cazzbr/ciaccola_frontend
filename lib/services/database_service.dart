import 'package:path/path.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static Database? _db;
  static const _dbName = 'p2p_chat.db';
  static const messagesTable = 'messages';

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $messagesTable (
            localId INTEGER PRIMARY KEY AUTOINCREMENT,
            messageId TEXT UNIQUE,
            contactId TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            isSentByMe INTEGER NOT NULL DEFAULT 0,
            isQueued INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      messagesTable,
      message.toMap()..remove('localId'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> getMessages(String contactId) async {
    final db = await database;
    final rows = await db.query(
      messagesTable,
      where: 'contactId = ? AND deleted = 0',
      whereArgs: [contactId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<List<ChatMessage>> getQueuedMessages(String contactId) async {
    final db = await database;
    final rows = await db.query(
      messagesTable,
      where: 'contactId = ? AND isQueued = 1 AND deleted = 0',
      whereArgs: [contactId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> markMessageDelivered(String messageId) async {
    final db = await database;
    await db.update(
      messagesTable,
      {'isQueued': 0},
      where: 'messageId = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteForMeAndHide(String messageId) async {
    final db = await database;
    await db.update(
      messagesTable,
      {'deleted': 1},
      where: 'messageId = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<String>> getChatContactIds() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT contactId FROM $messagesTable WHERE deleted = 0
    ''');
    return rows.map((row) => row['contactId'] as String).toList();
  }
}
