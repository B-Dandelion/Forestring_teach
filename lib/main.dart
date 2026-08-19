import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_gate.dart';
import 'core/config/app_config.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'ver2/Data/constant_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  await Firebase.initializeApp();

  final authController = AuthController(
    AuthRepository(),
  );

  await authController.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: authController,
        ),

        // v2 Firebase providers.
        // Remove after the v3 migration is complete.
        ChangeNotifierProvider(
          create: (_) => UserProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => LessonProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => SlotProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => MasterProvider(),
        ),
      ],
      child: const ForestringTeacher(),
    ),
  );
}

class ForestringTeacher extends StatelessWidget {
  const ForestringTeacher({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('ko', 'KR'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        title: 'Forestring_teacher',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: PRIMARY_COLOR,
          ),
          useMaterial3: true,
        ),
        home: const AppGate(),
      ),
    );
  }
}
