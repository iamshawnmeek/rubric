import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/grading_objectives_landing.dart';
import 'package:rubric/landing.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Colors.transparent,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: secondary,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: GradingObjectivesLanding(), //Landing
    );
  }
}
