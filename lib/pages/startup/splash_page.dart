// ignore_for_file: use_build_context_synchronously

// packages
import 'package:flutter/material.dart';
import 'package:secondstudent/globals/static/static_pages/static_load.dart';
import '../../globals/database.dart';
import 'home_page.dart';
import 'file_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/*
Splash Page Class
- Displays static loading screen while processing authorization
-
Page to redirect users to the appropriate page depending on the initial auth state.
- Ensures auth, if not, forces auth, which improves security. Also allows for RLS to be implemented properly.
- If no auth, show user signup page
- If auth, continue to home page
 */

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  SplashPageState createState() => SplashPageState();
}

class SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Defer navigation to after first frame to avoid build-time nav
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirect();
    });
  }

  // Redirects based on auth state
  // Additionally redirect based on if the folder exists or not 

  // TODO : need to force a value to be in path to files before continuing 
  Future<void> _redirect() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String pathValue = prefs.getString('path_to_files') ?? '';
    final bool hasPath = pathValue.isNotEmpty;

    if (!hasPath) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => FileStorage()),
        (route) => false,
      );
      return;
    }

    await DataBase.init();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StaticLoad();
  }
}
