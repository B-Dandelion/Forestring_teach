import 'package:flutter/material.dart';
import 'package:forestring_teach/Data/constant.dart';
import 'package:forestring_teach/Intro_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const Forestring());
}

class Forestring extends StatelessWidget {
  const Forestring({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Forestring_teach',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: PRIMARY_COLOR),
          useMaterial3: true,
        ),
        home: const IntroPage()
    );
  }
}