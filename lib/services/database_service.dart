import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_record.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('data_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE data_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        date_of_birth TEXT NOT NULL,
        gender TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        email TEXT NOT NULL,
        address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        location_method TEXT NOT NULL,
        notes TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE offline_regions(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        style_url TEXT NOT NULL,
        min_zoom REAL NOT NULL,
        max_zoom REAL NOT NULL,
        north REAL NOT NULL,
        south REAL NOT NULL,
        east REAL NOT NULL,
        west REAL NOT NULL,
        status TEXT NOT NULL,
        tile_count INTEGER DEFAULT 0,
        size_bytes INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_error TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_regions(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          style_url TEXT NOT NULL,
          min_zoom REAL NOT NULL,
          max_zoom REAL NOT NULL,
          north REAL NOT NULL,
          south REAL NOT NULL,
          east REAL NOT NULL,
          west REAL NOT NULL,
          status TEXT NOT NULL,
          tile_count INTEGER DEFAULT 0,
          size_bytes INTEGER DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_error TEXT
        )
      ''');
    }
  }

  Future<int> insertRecord(DataRecord record) async {
    final db = await database;
    return await db.insert('data_records', record.toMap());
  }

  Future<List<DataRecord>> getAllRecords() async {
    final db = await database;
    final result = await db.query('data_records', orderBy: 'created_at DESC');
    return result.map((map) => DataRecord.fromMap(map)).toList();
  }

  Future<DataRecord?> getRecord(int id) async {
    final db = await database;
    final result = await db.query(
      'data_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (result.isNotEmpty) {
      return DataRecord.fromMap(result.first);
    }
    return null;
  }

  Future<int> updateRecord(DataRecord record) async {
    final db = await database;
    return await db.update(
      'data_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;
    return await db.delete(
      'data_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertOfflineRegion(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'offline_regions',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getOfflineRegionsRaw() async {
    final db = await database;
    return db.query(
      'offline_regions',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteOfflineRegion(String id) async {
    final db = await database;
    await db.delete(
      'offline_regions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateOfflineRegionStatus(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final db = await database;
    await db.update(
      'offline_regions',
      patch,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}