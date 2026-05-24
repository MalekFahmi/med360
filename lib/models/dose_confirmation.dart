enum DoseStatus { taken, missed, pending }

class DoseConfirmation {
  final String id;
  final String medicationId;
  final String medicationName;
  final String scheduledTime;
  final DateTime scheduledDate;
  final DateTime? confirmedAt;
  final DoseStatus status;
  final bool caregiverNotified;
  final bool secondReminderSent;

  const DoseConfirmation({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.scheduledTime,
    required this.scheduledDate,
    this.confirmedAt,
    required this.status,
    this.caregiverNotified = false,
    this.secondReminderSent = false,
  });

  bool isOnDate(DateTime date) =>
      scheduledDate.year == date.year &&
      scheduledDate.month == date.month &&
      scheduledDate.day == date.day;

  bool get isTaken => status == DoseStatus.taken;
  bool get isMissed => status == DoseStatus.missed;
  bool get isPending => status == DoseStatus.pending;

  Map<String, dynamic> toMap() => {
        'id': id,
        'medicationId': medicationId,
        'medicationName': medicationName,
        'scheduledTime': scheduledTime,
        'scheduledDate': scheduledDate.toIso8601String(),
        'confirmedAt': confirmedAt?.toIso8601String(),
        'status': status.name,
        'caregiverNotified': caregiverNotified,
        'secondReminderSent': secondReminderSent,
      };

  factory DoseConfirmation.fromMap(Map<String, dynamic> m) => DoseConfirmation(
        id: m['id'],
        medicationId: m['medicationId'],
        medicationName: m['medicationName'],
        scheduledTime: m['scheduledTime'],
        scheduledDate: DateTime.parse(m['scheduledDate']),
        confirmedAt:
            m['confirmedAt'] != null ? DateTime.parse(m['confirmedAt']) : null,
        status: DoseStatus.values.byName(m['status']),
        caregiverNotified: m['caregiverNotified'] ?? false,
        secondReminderSent: m['secondReminderSent'] ?? false,
      );

  DoseConfirmation copyWith({
    DoseStatus? status,
    DateTime? confirmedAt,
    bool? caregiverNotified,
    bool? secondReminderSent,
  }) =>
      DoseConfirmation(
        id: id,
        medicationId: medicationId,
        medicationName: medicationName,
        scheduledTime: scheduledTime,
        scheduledDate: scheduledDate,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        status: status ?? this.status,
        caregiverNotified: caregiverNotified ?? this.caregiverNotified,
        secondReminderSent: secondReminderSent ?? this.secondReminderSent,
      );
}
