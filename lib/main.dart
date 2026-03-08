import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mis_medicamentos/screens/onboarding/permissions_onboarding_screen.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';
import 'package:mis_medicamentos/widgets/material3_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _googleServerClientId =
    '359325916002-a5doifb4vel25fgg06c58dl83ls5nipn.apps.googleusercontent.com';
const _permissionsOnboardingDoneKey = 'permissions_onboarding_done';

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
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _loading = true;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadStartupState();
  }

  Future<void> _loadStartupState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone =
        prefs.getBool(_permissionsOnboardingDoneKey) ?? false;
    if (onboardingDone) {
      await NotificationsService.instance
          .syncTodayDoseNotificationsFromDatabase();
    }
    if (!mounted) return;
    setState(() {
      _showOnboarding = !onboardingDone;
      _loading = false;
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionsOnboardingDoneKey, true);
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();
    if (!mounted) return;
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2F80ED)),
        ),
      );
    }
    if (_showOnboarding) {
      return PermissionsOnboardingScreen(onContinue: _completeOnboarding);
    }
    return const Material3BottomNav();
  }
}
