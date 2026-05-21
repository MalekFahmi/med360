// FR3 — Medication Information Integration
// Represents a medication retrieved from LIMU Care (static data for now)

enum ReminderType { notification, alarm }

enum MedicationStatus { active, paused, completed }

class MedicationSchedule {
  final List<String> times; // e.g. ['08:00', '20:00']
  final String frequency;   // e.g. 'Twice daily'
  final String frequencyAr; // Arabic: 'مرتين يومياً'

  const MedicationSchedule({
    required this.times,
    required this.frequency,
    required this.frequencyAr,
  });

  Map<String, dynamic> toMap() => {
    'times': times,
    'frequency': frequency,
    'frequencyAr': frequencyAr,
  };

  factory MedicationSchedule.fromMap(Map<String, dynamic> map) =>
      MedicationSchedule(
        times: List<String>.from(map['times']),
        frequency: map['frequency'],
        frequencyAr: map['frequencyAr'],
      );
}

class Medication {
  final String id;
  final String name;
  final String nameAr;           // Arabic name — FR Arabic support
  final String dosage;           // e.g. '500mg'
  final String form;             // e.g. 'Tablet', 'Capsule'
  final String formAr;
  final String indication;       // e.g. 'Diabetes management'
  final String indicationAr;
  final String prescribedBy;
  final MedicationSchedule schedule;
  final ReminderType reminderType;
  final MedicationStatus status;
  final DateTime prescribedDate;
  final String? notes;
  final String? notesAr;

  const Medication({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.dosage,
    required this.form,
    required this.formAr,
    required this.indication,
    required this.indicationAr,
    required this.prescribedBy,
    required this.schedule,
    required this.reminderType,
    required this.status,
    required this.prescribedDate,
    this.notes,
    this.notesAr,
  });

  // Full display name with dosage
  String get displayName => '$name $dosage';
  String get displayNameAr => '$nameAr $dosage';

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'nameAr': nameAr,
    'dosage': dosage,
    'form': form,
    'formAr': formAr,
    'indication': indication,
    'indicationAr': indicationAr,
    'prescribedBy': prescribedBy,
    'schedule': schedule.toMap(),
    'reminderType': reminderType.name,
    'status': status.name,
    'prescribedDate': prescribedDate.toIso8601String(),
    'notes': notes,
    'notesAr': notesAr,
  };

  factory Medication.fromMap(Map<String, dynamic> map) => Medication(
    id: map['id'],
    name: map['name'],
    nameAr: map['nameAr'],
    dosage: map['dosage'],
    form: map['form'],
    formAr: map['formAr'],
    indication: map['indication'],
    indicationAr: map['indicationAr'],
    prescribedBy: map['prescribedBy'],
    schedule: MedicationSchedule.fromMap(map['schedule']),
    reminderType: ReminderType.values.byName(map['reminderType']),
    status: MedicationStatus.values.byName(map['status']),
    prescribedDate: DateTime.parse(map['prescribedDate']),
    notes: map['notes'],
    notesAr: map['notesAr'],
  );

  Medication copyWith({
    ReminderType? reminderType,
    MedicationStatus? status,
    String? notes,
    String? notesAr,
  }) =>
      Medication(
        id: id,
        name: name,
        nameAr: nameAr,
        dosage: dosage,
        form: form,
        formAr: formAr,
        indication: indication,
        indicationAr: indicationAr,
        prescribedBy: prescribedBy,
        schedule: schedule,
        reminderType: reminderType ?? this.reminderType,
        status: status ?? this.status,
        prescribedDate: prescribedDate,
        notes: notes ?? this.notes,
        notesAr: notesAr ?? this.notesAr,
      );
}