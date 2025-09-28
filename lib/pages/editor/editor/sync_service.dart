///// LATER ISSUE......

/*

import 'package:secondstudent/globals/database.dart';
import 'package:secondstudent/pages/startup/file_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncService {
  final SupabaseClient supabaseClient;

  SyncService(this.supabaseClient);

  Future<void> syncFiles() async {
    // Check if the user is authenticated
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      print('User is not authenticated. Sync denied.');
      return;
    }

    // Get the saved path from FileStorage
    final fileStorage = FileStorage();
    final savedPath = await fileStorage._getSavedPath(); // Assuming _getSavedPath is accessible

    if (savedPath == null || savedPath.isEmpty) {
      print('No folder selected. Sync denied.');
      return;
    }

    final directory = Directory(savedPath);
    if (!await directory.exists()) {
      print('Directory does not exist. Sync denied.');
      return;
    }

    // Get all files in the directory
    final files = directory.listSync();

    for (var file in files) {
      if (file is File) {
        final fileName = file.uri.pathSegments.last;
        final fileBytes = await file.readAsBytes();

        // Upload file to Supabase storage
        final response = await supabaseClient.storage.from('your_bucket_name').upload(fileName, fileBytes);

        if (response.error != null) {
          print('Failed to upload $fileName: ${response.error!.message}');
        } else {
          print('Successfully uploaded $fileName');
        }
      }
    }
  }
}

*/