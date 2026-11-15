import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AttachmentDraft {
  const AttachmentDraft({
    required this.filePath,
    required this.mimeType,
    required this.fileSize,
    required this.sha256,
  });

  final String filePath;
  final String mimeType;
  final int fileSize;
  final String sha256;
}

class AttachmentService {
  AttachmentService._();

  static final ImagePicker _picker = ImagePicker();

  static Future<AttachmentDraft?> pickImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 86,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw StateError('Selected image is empty');
    final digest = sha256.convert(bytes).toString();
    final extension = p.extension(picked.path).toLowerCase();
    final safeExtension = ['.jpg', '.jpeg', '.png', '.webp'].contains(extension)
        ? extension
        : '.jpg';

    final documents = await getApplicationDocumentsDirectory();
    final directory =
        Directory(p.join(documents.path, 'purchase_ledger', 'attachments'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final target = File(p.join(directory.path, '$digest$safeExtension'));
    if (!await target.exists()) {
      await target.writeAsBytes(bytes, flush: true);
    }
    final mime = switch (safeExtension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    return AttachmentDraft(
      filePath: target.path,
      mimeType: mime,
      fileSize: bytes.length,
      sha256: digest,
    );
  }

  static Future<int> save(
    DatabaseExecutor executor, {
    required AttachmentDraft draft,
    required String entityType,
    required int entityId,
  }) {
    return executor.insert('attachments', {
      'entity_type': entityType,
      'entity_id': entityId,
      'file_path': draft.filePath,
      'mime_type': draft.mimeType,
      'file_size': draft.fileSize,
      'sha256': draft.sha256,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteFileIfUnreferenced(
    Database db,
    String filePath,
  ) async {
    final references = await db.query(
      'attachments',
      columns: ['id'],
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    if (references.isNotEmpty) return;
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}
