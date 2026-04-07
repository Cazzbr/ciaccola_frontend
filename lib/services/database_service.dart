import 'package:path/path.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact_invite.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqlite_api;
import 'database_factory.dart';

class DatabaseService {
  static sqlite_api.Database? _db;
  static const _dbName = 'p2p_chat.db';
  static const messagesTable = 'messages';
  static const invitesTable = 'contact_invites';

  Future<sqlite_api.Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<sqlite_api.Database> _init() async {
    final path = join(await databaseFactory.getDatabasesPath(), _dbName);
    return databaseFactory.openDatabase(
      path,
      options: sqlite_api.OpenDatabaseOptions(
        version: 2,
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
          await db.execute('''
            CREATE TABLE $invitesTable (
              fromUserId TEXT PRIMARY KEY,
              fromUsername TEXT NOT NULL,
              timestamp INTEGER NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $invitesTable (
                fromUserId TEXT PRIMARY KEY,
                fromUsername TEXT NOT NULL,
                timestamp INTEGER NOT NULL
              )
            ''');
          }
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Messages
  // -------------------------------------------------------------------------

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      messagesTable,
      message.toMap()..remove('localId'),
      conflictAlgorithm: sqlite_api.ConflictAlgorithm.replace,
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

  Future<ChatMessage?> getLastMessage(String contactId) async {
    final db = await database;
    final rows = await db.query(
      messagesTable,
      where: 'contactId = ? AND deleted = 0',
      whereArgs: [contactId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ChatMessage.fromMap(rows.first);
  }

  Future<List<String>> getChatContactIds() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT contactId FROM $messagesTable WHERE deleted = 0',
    );
    return rows.map((row) => row['contactId'] as String).toList();
  }

  // -------------------------------------------------------------------------
  // Contact invites
  // -------------------------------------------------------------------------

  Future<void> insertInvite(ContactInvite invite) async {
    final db = await database;
    await db.insert(
      invitesTable,
      invite.toMap(),
      conflictAlgorithm: sqlite_api.ConflictAlgorithm.replace,
    );
  }

  Future<List<ContactInvite>> getActiveInvites() async {
    final db = await database;
    final rows = await db.query(invitesTable, orderBy: 'timestamp DESC');
    return rows.map(ContactInvite.fromMap).toList();
  }

  Future<void> deleteInvite(String fromUserId) async {
    final db = await database;
    await db.delete(invitesTable, where: 'fromUserId = ?', whereArgs: [fromUserId]);
  }
}
