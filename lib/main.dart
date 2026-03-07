import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';
import 'package:mis_medicamentos/widgets/material3_bottom_nav.dart';

const _googleServerClientId =
    '359325916002-a5doifb4vel25fgg06c58dl83ls5nipn.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
      await GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
      );
    }
    await initializeDateFormatting('es_ES');
    await NotificationsService.instance.initialize();
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();
  } catch (error, stackTrace) {
    debugPrint('Startup initialization error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      locale: const Locale('es', 'ES'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],
      home: const Material3BottomNav(),
    );
  }
}
