import 'package:flutter/material.dart';

const Color primaryColor = Color(0xff003717);
const Color secondaryColor = Color(0xff708C7A);
const Color ivoryColor = Color(0xffF5F1E8);
const Color neutralIvory = Color(0xffF2F3EE);
const Color personalScheduleColor = Color(0xff75548C);

const TextStyle forestringTextStyle = TextStyle(
  color: Colors.black,
  fontFamily: 'ELAND',
  fontWeight: FontWeight.w300,
);

ThemeData buildForestringTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.white,
  );
}
