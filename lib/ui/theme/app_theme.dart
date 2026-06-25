import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const teal = Color(0xFF0F766E);
  static const tealDark = Color(0xFF115E59);
  static const tealLight = Color(0xFFE0F5F1);
  static const mint = Color(0xFFCCFBF1);
  static const navy = Color(0xFF132F45);
  static const sky = Color(0xFF256EA8);
  static const skyLight = Color(0xFFE8F2FB);
  static const amber = Color(0xFFB7791F);
  static const amberLight = Color(0xFFFFF2D6);
  static const red = Color(0xFFD94A4A);
  static const redLight = Color(0xFFFDECEC);
  static const blue = Color(0xFF2F80D1);
  static const blueLight = Color(0xFFE6F0FB);
  static const green = Color(0xFF2F855A);
  static const greenLight = Color(0xFFE5F4EA);
  static const grayLight = Color(0xFFF1F5F7);
  static const pageTint = Color(0xFFF3F7F8);
  static const surface = Color(0xFFFEFFFF);
  static const surfaceMuted = Color(0xFFF7FAFB);
  static const border = Color(0xFFDDE7EA);
  static const grayMid = Color(0xFF687982);
  static const grayDark = Color(0xFF263238);
  static const shadow = Color(0x1F31515C);
  static const white = Colors.white;
}

class AppTextStyles {
  AppTextStyles._();
  static const screenTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.navy,
    height: 1.18,
  );
  static const screenSub = TextStyle(
    fontSize: 16,
    color: AppColors.grayMid,
    height: 1.35,
  );
  static const sectionLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.grayMid,
    letterSpacing: 0,
    height: 1.25,
  );
  static const medName = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.navy,
    height: 1.22,
  );
  static const medDetail = TextStyle(
    fontSize: 15,
    color: AppColors.grayMid,
    height: 1.35,
  );
  static const metricValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.grayDark,
  );
  static const metricLabel = TextStyle(
    fontSize: 14,
    color: AppColors.grayMid,
    height: 1.25,
  );
  static const badgeText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
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
