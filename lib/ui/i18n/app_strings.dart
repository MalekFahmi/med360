import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class AppStrings {
  final bool isArabic;

  const AppStrings(this.isArabic);

  static AppStrings of(BuildContext context) =>
      AppStrings(context.watch<AuthProvider>().arabicMode);

  String pick(String arabic, String english) => isArabic ? arabic : english;

  String get home => isArabic ? 'الرئيسية' : 'Home';
  String get medications => isArabic ? 'أدويتي' : 'Meds';
  String get reports => isArabic ? 'التقارير' : 'Reports';
  String get care => isArabic ? 'الرعاية' : 'Care';
  String get settings => isArabic ? 'الإعدادات' : 'Settings';
  String get logout => isArabic ? 'تسجيل الخروج' : 'Log out';
  String get language => isArabic ? 'اللغة' : 'Language';
  String get arabic => isArabic ? 'العربية' : 'Arabic';
  String get english => 'English';
  String get patients => isArabic ? 'المرضى' : 'Patients';
  String get notifications => isArabic ? 'التنبيهات' : 'Notifications';
  String get noReports => isArabic ? 'لا توجد تقارير' : 'No reports';
  String get noNotifications =>
      isArabic ? 'لا توجد تنبيهات' : 'No notifications';
  String get patient => pick('مريض', 'Patient');
  String get doctor => pick('الطبيب', 'Doctor');
  String get caregiver => pick('مرافق', 'Caregiver');
  String get add => pick('إضافة', 'Add');
  String get create => pick('إنشاء', 'Create');
  String get link => pick('ربط', 'Link');
  String get archive => pick('أرشفة', 'Archive');
  String get reviewed => pick('تمت المراجعة', 'Reviewed');
  String get newItem => pick('جديد', 'New');
  String get active => pick('نشط', 'Active');
  String get paused => pick('متوقف', 'Paused');
  String get taken => pick('مأخوذة', 'Taken');
  String get missed => pick('فائتة', 'Missed');
  String get pending => pick('معلقة', 'Pending');
  String get rate => pick('النسبة', 'Rate');
  String get noPhone => pick('بدون رقم هاتف', 'No phone number');
  String get sharedReports => pick('تقارير مشتركة', 'Shared reports');
  String get noSharedReports =>
      pick('لا توجد تقارير مشتركة', 'No shared reports');
  String get sharedReportsHint => pick(
        'ستظهر هنا التقارير التي يشاركها المرضى معك.',
        'Reports patients share with you will appear here.',
      );
  String get noPatients => pick('لا يوجد مرضى', 'No patients');
  String get noPatientsCaregiverHint => pick(
        'أضف مريضا أو اربطه برقم الهاتف',
        'Create or link a patient by phone number.',
      );
  String get noPatientsDoctorHint => pick(
        'اربط مريضا برقم الهاتف لعرض أدويته وتقاريره.',
        'Link a patient by phone number to view medications and reports.',
      );
  String get addPatient => pick('إضافة مريض', 'Add patient');
  String get linkPatient => pick('ربط مريض', 'Link patient');
  String get patientPhone => pick('رقم هاتف المريض', 'Patient phone number');
  String get enterPatientPhone =>
      pick('أدخل رقم هاتف المريض', 'Enter the patient phone number');
  String get linkPatientHint => pick(
        'أدخل رقم هاتف المريض كما هو مسجل في حسابه.',
        'Enter the patient phone number exactly as registered on the account.',
      );
  String get addMedication => pick('إضافة دواء', 'Add medication');
  String get noMedications => pick('لا توجد أدوية', 'No medications');
  String get noMedicationsYet =>
      pick('لا توجد أدوية بعد', 'No medications yet');
  String get addMedicationForPatient =>
      pick('أضف دواء لهذا المريض', 'Add a medication for this patient');
  String get todaysStatus => pick('حالة اليوم', 'Today status');
  String get remainingDoses => pick('الجرعات المتبقية', 'Remaining doses');
  String get handledDoses => pick('تم التعامل معها', 'Handled doses');
  String get noDosesToday => pick('لا توجد جرعات اليوم', 'No doses today');
  String get noDosesTodayHint => pick(
        'عندما يكون لديك جرعات مجدولة ستظهر هنا',
        'Scheduled doses will appear here.',
      );
  String get addFirstMedicationHint => pick(
      'اذهب إلى أدويتي وأضف أول دواء', 'Go to Meds and add the first one.');
  String get dashboardSubtitle =>
      pick('تابع جرعاتك بسهولة اليوم', 'Track today’s doses easily.');
  String get adherenceStreak => pick('سلسلة الالتزام', 'Adherence streak');
  String get doneForToday =>
      pick('انتهيت من جرعات اليوم', 'You are done for today');
  String get doseTime => pick('وقت الجرعة', 'Dose time');
  String get tookIt => pick('أخذتها', 'Took it');
  String get adherenceSummary => pick('ملخص الالتزام', 'Adherence summary');
  String get adherence => pick('الالتزام', 'Adherence');
  String get medicationDetails => pick('تفاصيل الأدوية', 'Medication details');
  String get noMedicationDetails =>
      pick('لا توجد تفاصيل أدوية', 'No medication details');
  String get uploadedFile => pick('ملف مرفوع', 'Uploaded file');
  String get report => pick('تقرير', 'Report');

  String greeting(String name) => name.trim().isEmpty
      ? pick('مرحبا', 'Hello')
      : pick('مرحبا، $name', 'Hello, $name');

  String takenOfTotal(int taken, int total) => total == 0
      ? noDosesToday
      : pick('تم أخذ $taken من $total جرعات', '$taken of $total doses taken');

  String bestStreak(int days) =>
      pick('أفضل سلسلة: $days يوم', 'Best streak: $days days');

  String days(int days) => pick('$days يوم', '$days days');

  String doseLoggedTaken(String medicationName) => pick(
      'تم تسجيل $medicationName كمأخوذ', '$medicationName marked as taken');

  String get doseLoggedMissed =>
      pick('تم تسجيل الجرعة كفائتة', 'Dose marked as missed');

  String doseTimeValue(String time) =>
      pick('$doseTime: $time', '$doseTime: $time');

  String adherencePercent(int percent) =>
      pick('معدل الالتزام $percent%', 'Adherence $percent%');

  String reportTitle(String patientName) =>
      pick('تقرير $patientName', '$patientName report');

  String medicationsFor(String patientName) =>
      pick('أدوية $patientName', '$patientName medications');

  String typeLabel(String type) => switch (type) {
        'daily' => pick('تقرير يومي', 'Daily report'),
        'weekly' => pick('تقرير أسبوعي', 'Weekly report'),
        'uploaded' => uploadedFile,
        _ => pick('تقرير شهري', 'Monthly report'),
      };

  String dailyDoses(double value) => pick(
      'الجرعات اليومية: ${formatNumber(value)}',
      'Daily doses: ${formatNumber(value)}');

  String times(String value) => pick('الأوقات: $value', 'Times: $value');

  String indication(String value) => pick('الاستخدام: $value', 'Use: $value');

  String notes(String value) => pick('ملاحظات: $value', 'Notes: $value');

  String remainingQuantity(int value) =>
      pick('المتبقي $value جرعة', '$value doses left');

  String medicationReportStats({
    required int taken,
    required int missed,
    required int pending,
  }) =>
      pick(
        'مأخوذة $taken • فائتة $missed • معلقة $pending',
        'Taken $taken • Missed $missed • Pending $pending',
      );

  String formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}
