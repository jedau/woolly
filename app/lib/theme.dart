import 'package:flutter/material.dart';

const bg = Color(0xFF1B1916);
const sidebar = Color(0xFF141210);
const panel = Color(0xFF24201C);
const raised = Color(0xFF2C2824);
const line = Color(0xFF3A322C);
const ink = Color(0xFFE8E0D4);
const muted = Color(0xFF9A8B7A);
const amber = Color(0xFFE0A15C);
const credit = Color(0xFFA6C178);
const dispute = Color(0xFFD16B6B);

ThemeData woollyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      surface: panel,
      primary: amber,
      onPrimary: Color(0xFF1B1916),
      secondary: amber,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    dividerColor: line,
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: raised,
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: amber),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: amber,
        foregroundColor: const Color(0xFF1B1916),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}
