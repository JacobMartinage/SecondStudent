import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localstorage/localstorage.dart';
import 'dart:async';
import 'dart:io'; 

// pages
import 'pages/startup/splash_page.dart';
import 'package:secondstudent/globals/database.dart';
import 'package:secondstudent/globals/notification_service.dart';
import 'package:secondstudent/globals/static/themes.dart';
import 'package:secondstudent/globals/stream_signal.dart';
import 'package:secondstudent/globals/account_service.dart';
import 'package:secondstudent/pages/editor/sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

// initialize main stream signal
final StreamController<StreamSignal> mainStream =
    StreamController<StreamSignal>();

void main() async {
  // init supabase

  await DataBase.tryInitialize();

  // set orientation for chrome
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // notifs
  await NotificationService.setup();

  // init local storage
  await initLocalStorage();

  final prefs = await SharedPreferences.getInstance();
  final p = prefs.getString('path_to_files')?.trim();

  if (p != null && p.isNotEmpty) {
    await Sync().syncDown(p);
  }


  // double check theme initialized
  Themes.checkTheme();

  // ensure theme stream has a listener
  if (!mainStream.hasListener) {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.setup(); // must be awaited before runApp
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  //Application root widget
  @override
  Widget build(BuildContext context) {
    //Streambuilder; refreshes on theme change
    return StreamBuilder(
      stream: mainStream.stream,
      initialData: StreamSignal(
        streamController: mainStream,
        newData: {'theme': AccountService.account['theme'] ?? 'Scarlet'},
      ),
      builder: (context, snapshot) {
        //Primary application
        return MaterialApp(
          title: 'SecondStudent',
          theme:
              Themes.themeData[snapshot.data?.data['theme']] ??
              Themes.themeData['Scarlet'],
          //Loading screen; processes auth
          home: const SplashPage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
