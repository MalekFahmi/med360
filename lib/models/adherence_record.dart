class AdherenceRecord {
  final String medicationId;
  final String medicationName;
  final int year;
  final int month;
  final int totalDoses;
  final int takenDoses;
  final int missedDoses;
  final int pendingDoses;

  const AdherenceRecord({
    required this.medicationId,
    required this.medicationName,
    required this.year,
    required this.month,
    required this.totalDoses,
    required this.takenDoses,
    required this.missedDoses,
    required this.pendingDoses,
  });

  double get adherenceRate {
    final resolved = takenDoses + missedDoses;
    if (resolved == 0) return 0.0;
    return takenDoses / resolved;
  }

  String get adherencePercentage => '${(adherenceRate * 100).round()}%';

  String get adherenceLabel {
    final p = adherenceRate * 100;
    if (p >= 80) return 'Good';
    if (p >= 60) return 'Fair';
    return 'Poor';
  }

  String get adherenceLabelAr {
    final p = adherenceRate * 100;
    if (p >= 80) return 'جيد';
    if (p >= 60) return 'مقبول';
    return 'ضعيف';
  }
}

class MonthlyAdherenceSummary {
  final int year;
  final int month;
  final List<AdherenceRecord> perMedication;

  const MonthlyAdherenceSummary({
    required this.year,
    required this.month,
    required this.perMedication,
  });

  int get takenDoses  => perMedication.fold(0, (s, r) => s + r.takenDoses);
  int get missedDoses => perMedication.fold(0, (s, r) => s + r.missedDoses);

  double get overallAdherenceRate {
    final resolved = takenDoses + missedDoses;
    if (resolved == 0) return 0.0;
    return takenDoses / resolved;
  }

  String get overallPercentage => '${(overallAdherenceRate * 100).round()}%';

  String get adherenceLabel {
    final p = overallAdherenceRate * 100;
    if (p >= 80) return 'Good';
    if (p >= 60) return 'Fair';
    return 'Poor';
  }

  String get monthLabel {
    const months = ['','January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    return '${months[month]} $year';
  }

  String get monthLabelAr {
    const m = ['','يناير','فبراير','مارس','أبريل','مايو','يونيو',
        'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    return '${m[month]} $year';
  }
}