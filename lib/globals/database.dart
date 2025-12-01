import 'package:supabase_flutter/supabase_flutter.dart';

/*
Database is just used to store various functions used throughout the app
- just a helper class to prevent having to remake code for basic database functionality
- also centralizes major interactions with the supabase
- central file for reused database interactions

THIS FILE COMMUNICATES WITH SUPABASE DATABASE SOLELY
 */

// create variable for database which will be accessed later
final SupabaseClient supabase = Supabase.instance.client;

class DataBase {
  // sample: can define a peice of data that is consistent, and then update the variable
  // static List<Map<String, dynamic>> ideas = [];

  static Future<void> init() async {}

  // init supabase
  static Future<bool> tryInitialize() async {
    // add privacy policy on initialize
    try {
      await Supabase.initialize(
        // url and anonkey of supabase db
        url: 'https://vuuyygpagfpklganlrue.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1dXl5Z3BhZ2Zwa2xnYW5scnVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg5Mjk0NDEsImV4cCI6MjA3NDUwNTQ0MX0.cDlIrNZwH-8UmjwoMvseSofqfPKDY0hrSKsbCbNkTes',
      );
      return true;
    } catch (e) {
      // Print error for debug
      return false;
    }
  }

  // sample db function

  // report error to supabase table
  static Future<void> reportError(
    String description,
    String type,
    String reference,
  ) async {
    String? uuid = (await supabase.auth.getUser()).user?.id;
    await supabase.from("errors").insert({
      'description': description,
      'type': type,
      'reference': reference,
      'uuid': uuid,
    });
  }

  // sample supabase edge invocation
  //   final res = await supabase.functions.invoke('gpt-description', body: {'idea': context});
}
