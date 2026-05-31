// Medication model — standalone version.
// The patient creates and owns all their medication records directly.

enum ReminderType { notification, alarm }

enum MedicationStatus { active, paused, completed }

enum MedicationForm {
  tablet,
  capsule,
  liquid,
  injection,
  drops,
  inhaler,
  patch,
  other
}

class ReminderTime {
  final int hour;
  final int minute;

  const ReminderTime({required this.hour, required this.minute});

  String get display =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {'hour': hour, 'minute': minute};

  factory ReminderTime.fromMap(Map<String, dynamic> m) =>
      ReminderTime(hour: m['hour'], minute: m['minute']);

  factory ReminderTime.fromString(String s) {
    final parts = s.split(':');
    return ReminderTime(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}

class Medication {
  final String id;
  final String name;
  final String nameAr;
  final String dosage; // e.g. "500mg"
  final MedicationForm form;
  final String indication; // what it's for — entered by patient
  final String indicationAr;
  final List<ReminderTime> reminderTimes;
  final ReminderType reminderType;
  final MedicationStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final int quantityRemaining;
  final double dosesPerDay;
  final int refillThreshold;
  final String? notes;
  final String? notesAr;

  const Medication({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.dosage,
    required this.form,
    required this.indication,
    required this.indicationAr,
    required this.reminderTimes,
    required this.reminderType,
    required this.status,
    required this.startDate,
    this.endDate,
    this.quantityRemaining = 0,
    this.dosesPerDay = 1,
    this.refillThreshold = 7,
    this.notes,
    this.notesAr,
  });

  String get displayName => '$name $dosage';
  String get displayNameAr => '$nameAr $dosage';
  double get estimatedDaysRemaining =>
      dosesPerDay <= 0 ? 0 : quantityRemaining / dosesPerDay;
  bool get needsRefill =>
      quantityRemaining > 0 && estimatedDaysRemaining <= refillThreshold;

  String get formLabel => switch (form) {
        MedicationForm.tablet => 'Tablet',
        MedicationForm.capsule => 'Capsule',
        MedicationForm.liquid => 'Liquid',
        MedicationForm.injection => 'Injection',
        MedicationForm.drops => 'Drops',
        MedicationForm.inhaler => 'Inhaler',
        MedicationForm.patch => 'Patch',
        MedicationForm.other => 'Other',
      };

  String get formLabelAr => switch (form) {
        MedicationForm.tablet => 'قرص',
        MedicationForm.capsule => 'كبسولة',
        MedicationForm.liquid => 'سائل',
        MedicationForm.injection => 'حقنة',
        MedicationForm.drops => 'قطرات',
        MedicationForm.inhaler => 'بخاخ',
        MedicationForm.patch => 'لصقة',
        MedicationForm.other => 'أخرى',
      };

  String get frequencyLabel {
    final n = reminderTimes.length;
    return switch (n) {
      1 => 'Once daily',
      2 => 'Twice daily',
      3 => '3 times daily',
      _ => '$n times daily',
    };
  }

  String get frequencyLabelAr {
    final n = reminderTimes.length;
    return switch (n) {
      1 => 'مرة يومياً',
      2 => 'مرتين يومياً',
      3 => '3 مرات يومياً',
      _ => '$n مرات يومياً',
    };
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameAr': nameAr,
        'dosage': dosage,
        'form': form.name,
        'indication': indication,
        'indicationAr': indicationAr,
        'reminderTimes': reminderTimes.map((t) => t.toMap()).toList(),
        'reminderType': reminderType.name,
        'status': status.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'quantityRemaining': quantityRemaining,
        'dosesPerDay': dosesPerDay,
        'refillThreshold': refillThreshold,
        'notes': notes,
        'notesAr': notesAr,
      };

  factory Medication.fromMap(Map<String, dynamic> m) => Medication(
        id: m['id'],
        name: m['name'],
        nameAr: m['nameAr'] ?? m['name'],
        dosage: m['dosage'],
        form: MedicationForm.values.byName(m['form']),
        indication: m['indication'] ?? '',
        indicationAr: m['indicationAr'] ?? '',
        reminderTimes: (m['reminderTimes'] as List)
            .map((t) => ReminderTime.fromMap(t))
            .toList(),
        reminderType: ReminderType.values.byName(m['reminderType']),
        status: MedicationStatus.values.byName(m['status']),
        startDate: DateTime.parse(m['startDate']),
        endDate: m['endDate'] != null ? DateTime.tryParse(m['endDate']) : null,
        quantityRemaining: m['quantityRemaining'] ?? 0,
        dosesPerDay: (m['dosesPerDay'] as num?)?.toDouble() ?? 1,
        refillThreshold: m['refillThreshold'] ?? 7,
        notes: m['notes'],
        notesAr: m['notesAr'],
      );

  Medication copyWith({
    String? name,
    String? nameAr,
    String? dosage,
    MedicationForm? form,
    String? indication,
    String? indicationAr,
    List<ReminderTime>? reminderTimes,
    ReminderType? reminderType,
    MedicationStatus? status,
    DateTime? endDate,
    int? quantityRemaining,
    double? dosesPerDay,
    int? refillThreshold,
    String? notes,
    String? notesAr,
  }) =>
      Medication(
        id: id,
        name: name ?? this.name,
        nameAr: nameAr ?? this.nameAr,
        dosage: dosage ?? this.dosage,
        form: form ?? this.form,
        indication: indication ?? this.indication,
        indicationAr: indicationAr ?? this.indicationAr,
        reminderTimes: reminderTimes ?? this.reminderTimes,
        reminderType: reminderType ?? this.reminderType,
        status: status ?? this.status,
        startDate: startDate,
        endDate: endDate ?? this.endDate,
        quantityRemaining: quantityRemaining ?? this.quantityRemaining,
        dosesPerDay: dosesPerDay ?? this.dosesPerDay,
        refillThreshold: refillThreshold ?? this.refillThreshold,
        notes: notes ?? this.notes,
        notesAr: notesAr ?? this.notesAr,
      );
}
