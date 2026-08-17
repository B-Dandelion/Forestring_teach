import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:forestring_teacher_2/core/config/app_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:forestring_teacher_2/ver2/Intro.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  await Firebase.initializeApp();
  runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => UserProvider()), // UserProvider 등록
          ChangeNotifierProvider(create: (_) => LessonProvider()), // LessonProvider 등록
          ChangeNotifierProvider(create: (context) => SlotProvider()), // SlotProvider 추가!
          ChangeNotifierProvider(create: (context) => MasterProvider()),
        ],
        child: const Forestring_teacher(),
      ),
  );
}

class Forestring_teacher extends StatelessWidget {
  const Forestring_teacher({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: (){
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: MaterialApp(
            locale: Locale('en', 'US'),
            supportedLocales: const [
              Locale('en', 'US'),
              Locale('ko', 'KR'), // 한국어 지원 추가
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate, // iOS 스타일 피커 지원
            ],
            debugShowCheckedModeBanner: false,
            title: 'Forestring_teacher',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: PRIMARY_COLOR),
              useMaterial3: true,
            ),
            home: const Intro())
    );
  }
}