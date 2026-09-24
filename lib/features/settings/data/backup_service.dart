import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/storage/database_helper.dart';

class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Exports the database to a user-selected location
  Future<String?> exportDatabase() async {
    try {
      final dbFile = await _dbHelper.getDatabaseFile();
      if (!await dbFile.exists()) {
        return 'Database file not found.';
      }

      // Let user select directory (Desktop/USB/etc)
      String? outputPath = await FilePicker.platform.getDirectoryPath();
      
      if (outputPath == null) return null; // User cancelled

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final backupFileName = 'madarsa_backup_$timestamp.db';
      final backupPath = p.join(outputPath, backupFileName);

      await dbFile.copy(backupPath);
      return 'Backup successful: $backupFileName';
    } catch (e) {
      return 'Backup failed: $e';
    }
  }

  /// Restores the database from a user-selected file
  Future<String?> importDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // .db files often show up as any
      );

      if (result == null || result.files.single.path == null) return null;

      final backupFile = File(result.files.single.path!);
      final dbFile = await _dbHelper.getDatabaseFile();

      // Close current connection before replacing
      await _dbHelper.close();

      await backupFile.copy(dbFile.path);
      
      return 'Restore successful. Please restart the application.';
    } catch (e) {
      return 'Restore failed: $e';
    }
  }
}
