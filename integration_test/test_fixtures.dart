import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads the shared, non-sensitive synthetic voice sample from Storage
/// (`test_fixtures/voice_sample.m4a`) into a local temp file, rather than
/// bundling it inside the app for every install. Callers must already have
/// an authenticated Firebase user (see `storage.rules`).
Future<File> downloadVoiceSampleFixture() async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/voice_sample.m4a');
  await FirebaseStorage.instance
      .ref('test_fixtures/voice_sample.m4a')
      .writeToFile(file);
  return file;
}
