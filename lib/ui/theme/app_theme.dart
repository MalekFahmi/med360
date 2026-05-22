import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const teal = Color(0xFF1D9E75);
  static const tealDark = Color(0xFF085041);
  static const tealLight = Color(0xFFE1F5EE);
  static const amber = Color(0xFFBA7517);
  static const amberLight = Color(0xFFFAEEDA);
  static const red = Color(0xFFE24B4A);
  static const redLight = Color(0xFFFCEBEB);
  static const blue = Color(0xFF378ADD);
  static const blueLight = Color(0xFFE6F1FB);
  static const green = Color(0xFF639922);
  static const greenLight = Color(0xFFEAF3DE);
  static const grayLight = Color(0xFFF5F5F3);
  static const grayMid = Color(0xFF888780);
  static const grayDark = Color(0xFF2C2C2A);
  static const white = Colors.white;
}

class AppTextStyles {
  AppTextStyles._();
  static const screenTitle = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.grayDark);
  static const screenSub = TextStyle(fontSize: 13, color: AppColors.grayMid);
  static const sectionLabel = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.grayMid,
      letterSpacing: 0.5);
  static const medName = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.grayDark);
  static const medDetail = TextStyle(fontSize: 12, color: AppColors.grayMid);
  static const metricValue =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
  static const metricLabel = TextStyle(fontSize: 11, color: AppColors.grayMid);
  static const badgeText = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
}

class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  AppRadius._();
  static const sm = BorderRadius.all(Radius.circular(8));
  static const md = BorderRadius.all(Radius.circular(12));
  static const lg = BorderRadius.all(Radius.circular(16));
  static const pill = BorderRadius.all(Radius.circular(100));
}
