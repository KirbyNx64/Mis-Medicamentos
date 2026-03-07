import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'mis_medicamentos.db';
  static const int _dbVersion = 3;

  Database? _database;
  bool _schemaEnsured = false;
  final ValueNotifier<int> medicationsChangeToken = ValueNotifier<int>(0);

  Future<Database> get database async {
    _database ??= await _open();
    if (!_schemaEnsured) {
      await _ensureRuntimeSchema(_database!);
      _schemaEnsured = true;
    }
    return _database!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        active_ingredient TEXT,
        dose_amount REAL NOT NULL,
        dose_unit TEXT NOT NULL,
        form TEXT NOT NULL,
        route TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        instructions TEXT,
        diagnosis TEXT,
        prescribed_by TEXT,
        first_dose_at TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT,
        indefinite INTEGER NOT NULL DEFAULT 0,
        frequency_rule TEXT NOT NULL,
        days_of_week TEXT,
        stock_current INTEGER,
        stock_initial INTEGER,
        stock_minimum INTEGER,
        intake_quantity INTEGER NOT NULL DEFAULT 1,
        reminder_minutes_before INTEGER NOT NULL DEFAULT 15,
        reminder_sound INTEGER NOT NULL DEFAULT 1,
        reminder_vibration INTEGER NOT NULL DEFAULT 1,
        interactions_notes TEXT,
        side_effects_notes TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE medication_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        time_of_day TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE dose_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        scheduled_at TEXT NOT NULL,
        taken_at TEXT,
        status TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE medication_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'image',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notification_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_key TEXT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        kind TEXT NOT NULL,
        medication_form TEXT,
        scheduled_at TEXT,
        payload TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_schedule_medication ON medication_schedules(medication_id)',
    );
    await db.execute(
      'CREATE INDEX idx_logs_medication ON dose_logs(medication_id)',
    );
    await db.execute('CREATE INDEX idx_logs_status ON dose_logs(status)');
    await db.execute(
      'CREATE INDEX idx_notification_logs_created ON notification_logs(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_notification_logs_event_key ON notification_logs(event_key)',
    );
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        table: 'medications',
        column: 'intake_quantity',
        definition: 'INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        table: 'medications',
        column: 'stock_initial',
        definition: 'INTEGER',
      );
    }
    await _addColumnIfMissing(
      db,
      table: 'medications',
      column: 'first_dose_at',
      definition: 'TEXT',
    );
  }

  Future<void> _ensureRuntimeSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'medications',
      column: 'intake_quantity',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      table: 'medications',
      column: 'stock_initial',
      definition: 'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'medications',
      column: 'first_dose_at',
      definition: 'TEXT',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'image',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_key TEXT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        kind TEXT NOT NULL,
        medication_form TEXT,
        scheduled_at TEXT,
        payload TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await _addColumnIfMissing(
      db,
      table: 'notification_logs',
      column: 'medication_form',
      definition: 'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_logs_created ON notification_logs(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_logs_event_key ON notification_logs(event_key)',
    );
  }

  Future<Map<String, Object?>> _filterMedicationColumns(
    DatabaseExecutor db,
    Map<String, Object?> payload,
  ) async {
    return _filterTableColumns(db, table: 'medications', payload: payload);
  }

  Future<Map<String, Object?>> _filterTableColumns(
    DatabaseExecutor db, {
    required String table,
    required Map<String, Object?> payload,
  }) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
    final columns = tableInfo
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    return Map<String, Object?>.fromEntries(
      payload.entries.where((entry) => columns.contains(entry.key)),
    );
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
    final expected = column.toLowerCase().trim();
    final exists = tableInfo.any((row) {
      final name = row['name']?.toString().toLowerCase().trim();
      return name == expected;
    });
    if (!exists) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      } on DatabaseException catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('duplicate column name')) {
          rethrow;
        }
      }
    }
  }

  Future<int> createMedication(
    Map<String, Object?> medication, {
    List<String> times = const [],
  }) async {
    final db = await database;

    final medicationId = await db.transaction<int>((txn) async {
      final safeMedication = await _filterMedicationColumns(txn, medication);
      final medicationId = await txn.insert('medications', safeMedication);
      for (final time in times) {
        await txn.insert('medication_schedules', {
          'medication_id': medicationId,
          'time_of_day': time,
        });
      }
      return medicationId;
    });
    _notifyMedicationsChanged();
    return medicationId;
  }

  Future<void> updateMedication(
    int medicationId,
    Map<String, Object?> medication, {
    List<String> times = const [],
  }) async {
    final db = await database;

    await db.transaction<void>((txn) async {
      final safeMedication = await _filterMedicationColumns(txn, medication);
      await txn.update(
        'medications',
        {...safeMedication, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [medicationId],
      );

      await txn.delete(
        'medication_schedules',
        where: 'medication_id = ?',
        whereArgs: [medicationId],
      );

      for (final time in times) {
        await txn.insert('medication_schedules', {
          'medication_id': medicationId,
          'time_of_day': time,
        });
      }
    });
    _notifyMedicationsChanged();
  }

  Future<void> deleteMedication(int medicationId) async {
    final db = await database;
    final deleted = await db.delete(
      'medications',
      where: 'id = ?',
      whereArgs: [medicationId],
    );
    if (deleted > 0) {
      _notifyMedicationsChanged();
    }
  }

  Future<List<Map<String, Object?>>> getMedications() async {
    final db = await database;
    return db.query('medications', orderBy: 'name ASC');
  }

  Future<List<Map<String, Object?>>> getMedicationSchedules(
    int medicationId,
  ) async {
    final db = await database;
    return db.query(
      'medication_schedules',
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      orderBy: 'time_of_day ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAllMedicationSchedules() async {
    final db = await database;
    return db.query(
      'medication_schedules',
      orderBy: 'medication_id ASC, time_of_day ASC',
    );
  }

  Future<String?> getMedicationImageAttachmentPath(int medicationId) async {
    final db = await database;
    final rows = await db.query(
      'medication_attachments',
      columns: ['file_path'],
      where: 'medication_id = ? AND kind = ?',
      whereArgs: [medicationId, 'image'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['file_path']?.toString();
  }

  Future<Map<int, String>> getMedicationImageAttachmentPaths(
    Iterable<int> medicationIds,
  ) async {
    final ids = medicationIds.toSet().toList();
    if (ids.isEmpty) return const {};

    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'medication_attachments',
      columns: ['medication_id', 'file_path', 'id'],
      where: 'kind = ? AND medication_id IN ($placeholders)',
      whereArgs: ['image', ...ids],
      orderBy: 'id DESC',
    );

    final result = <int, String>{};
    for (final row in rows) {
      final medicationId = row['medication_id'] as int?;
      final filePath = row['file_path']?.toString();
      if (medicationId == null || filePath == null || filePath.isEmpty) {
        continue;
      }
      result.putIfAbsent(medicationId, () => filePath);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> getMedicationAttachments() async {
    final db = await database;
    return db.query(
      'medication_attachments',
      orderBy: 'medication_id ASC, id ASC',
    );
  }

  Future<void> replaceMedicationImageAttachment(
    int medicationId,
    String? filePath,
  ) async {
    final db = await database;
    await db.transaction<void>((txn) async {
      await txn.delete(
        'medication_attachments',
        where: 'medication_id = ? AND kind = ?',
        whereArgs: [medicationId, 'image'],
      );
      if (filePath == null || filePath.trim().isEmpty) return;
      await txn.insert('medication_attachments', {
        'medication_id': medicationId,
        'file_path': filePath.trim(),
        'kind': 'image',
      });
    });
    _notifyMedicationsChanged();
  }

  Future<int> createDoseLog(Map<String, Object?> log) async {
    final db = await database;
    return db.insert('dose_logs', log);
  }

  Future<bool> markDoseAsTaken({
    required int medicationId,
    required DateTime scheduledAt,
    required int intakeQuantity,
    DateTime? takenAt,
  }) async {
    final db = await database;
    final safeIntake = intakeQuantity <= 0 ? 1 : intakeQuantity;
    final takenAtValue = (takenAt ?? DateTime.now()).toIso8601String();

    final marked = await db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'dose_logs',
        columns: ['id'],
        where: 'medication_id = ? AND scheduled_at = ? AND status = ?',
        whereArgs: [medicationId, scheduledAt.toIso8601String(), 'taken'],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return false;
      }

      await txn.insert('dose_logs', {
        'medication_id': medicationId,
        'scheduled_at': scheduledAt.toIso8601String(),
        'taken_at': takenAtValue,
        'status': 'taken',
        'note': null,
      });

      await txn.rawUpdate(
        '''
        UPDATE medications
        SET stock_current = MAX(stock_current - ?, 0),
            updated_at = ?
        WHERE id = ?
          AND stock_current IS NOT NULL
        ''',
        [safeIntake, DateTime.now().toIso8601String(), medicationId],
      );

      return true;
    });

    if (marked) {
      _notifyMedicationsChanged();
    }
    return marked;
  }

  Future<List<Map<String, Object?>>> getDoseLogs({
    int? medicationId,
    String? status,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (medicationId != null) {
      where.add('medication_id = ?');
      args.add(medicationId);
    }

    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }

    return db.query(
      'dose_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'scheduled_at DESC',
    );
  }

  Future<void> createNotificationLog(Map<String, Object?> log) async {
    final db = await database;
    await _ensureNotificationLogsSchema(db);
    await db.insert('notification_logs', {
      ...log,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> upsertNotificationLogByEventKey({
    required String eventKey,
    required String title,
    required String body,
    required String kind,
    String? medicationForm,
    String? scheduledAt,
    String? payload,
  }) async {
    final db = await database;
    await _ensureNotificationLogsSchema(db);
    await db.transaction<void>((txn) async {
      final existing = await txn.query(
        'notification_logs',
        columns: ['id'],
        where: 'event_key = ?',
        whereArgs: [eventKey],
        limit: 1,
      );

      final data = <String, Object?>{
        'event_key': eventKey,
        'title': title,
        'body': body,
        'kind': kind,
        'medication_form': medicationForm,
        'scheduled_at': scheduledAt,
        'payload': payload,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (existing.isEmpty) {
        await txn.insert('notification_logs', data);
        return;
      }

      await txn.update(
        'notification_logs',
        data,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    });
  }

  Future<List<Map<String, Object?>>> getNotificationLogs({
    int limit = 200,
  }) async {
    final db = await database;
    await _ensureNotificationLogsSchema(db);
    return db.query(
      'notification_logs',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
  }

  Future<void> _ensureNotificationLogsSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_key TEXT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        kind TEXT NOT NULL,
        medication_form TEXT,
        scheduled_at TEXT,
        payload TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await _addColumnIfMissing(
      db,
      table: 'notification_logs',
      column: 'medication_form',
      definition: 'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_logs_created ON notification_logs(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_logs_event_key ON notification_logs(event_key)',
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
    _schemaEnsured = false;
  }

  void _notifyMedicationsChanged() {
    medicationsChangeToken.value++;
  }

  void notifyMedicationsChanged() {
    _notifyMedicationsChanged();
  }

  Future<void> replaceAllFromCloud({
    required List<Map<String, Object?>> medications,
    required List<Map<String, Object?>> medicationSchedules,
    required List<Map<String, Object?>> medicationAttachments,
    required List<Map<String, Object?>> doseLogs,
    required List<Map<String, Object?>> notificationLogs,
  }) async {
    final db = await database;
    await db.transaction<void>((txn) async {
      await txn.delete('notification_logs');
      await txn.delete('dose_logs');
      await txn.delete('medication_attachments');
      await txn.delete('medication_schedules');
      await txn.delete('medications');

      for (final row in medications) {
        final safe = await _filterTableColumns(
          txn,
          table: 'medications',
          payload: row,
        );
        if (safe.isNotEmpty) {
          await txn.insert('medications', safe);
        }
      }

      for (final row in medicationSchedules) {
        final safe = await _filterTableColumns(
          txn,
          table: 'medication_schedules',
          payload: row,
        );
        if (safe.isNotEmpty) {
          await txn.insert('medication_schedules', safe);
        }
      }

      for (final row in medicationAttachments) {
        final safe = await _filterTableColumns(
          txn,
          table: 'medication_attachments',
          payload: row,
        );
        if (safe.isNotEmpty) {
          await txn.insert('medication_attachments', safe);
        }
      }

      for (final row in doseLogs) {
        final safe = await _filterTableColumns(
          txn,
          table: 'dose_logs',
          payload: row,
        );
        if (safe.isNotEmpty) {
          await txn.insert('dose_logs', safe);
        }
      }

      for (final row in notificationLogs) {
        final safe = await _filterTableColumns(
          txn,
          table: 'notification_logs',
          payload: row,
        );
        if (safe.isNotEmpty) {
          await txn.insert('notification_logs', safe);
        }
      }
    });
    _notifyMedicationsChanged();
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction<void>((txn) async {
      await txn.delete('notification_logs');
      await txn.delete('dose_logs');
      await txn.delete('medication_attachments');
      await txn.delete('medication_schedules');
      await txn.delete('medications');
    });
    _notifyMedicationsChanged();
  }
}
