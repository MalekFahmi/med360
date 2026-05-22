enum NotificationChannel { sms, inApp, both }

class CaregiverNotification {
  final String id;
  final String caregiverId;
  final String caregiverName;
  final String patientId;
  final String patientName;
  final String? medicationId;
  final String? medicationName;
  final DateTime? missedAt;
  final DateTime sentAt;
  final NotificationChannel channel;
  final bool acknowledged;
  final String type; // 'missedDose' or 'caregiverAdded'

  const CaregiverNotification({
    required this.id,
    required this.caregiverId,
    required this.caregiverName,
    required this.patientId,
    required this.patientName,
    this.medicationId,
    this.medicationName,
    this.missedAt,
    required this.sentAt,
    required this.channel,
    this.acknowledged = false,
    this.type = 'missedDose',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'caregiverId': caregiverId,
        'caregiverName': caregiverName,
        'patientId': patientId,
        'patientName': patientName,
        'medicationId': medicationId,
        'medicationName': medicationName,
        'missedAt': missedAt?.toIso8601String(),
        'sentAt': sentAt.toIso8601String(),
        'channel': channel.name,
        'acknowledged': acknowledged,
        'type': type,
      };

  factory CaregiverNotification.fromMap(Map<String, dynamic> m) =>
      CaregiverNotification(
        id: m['id'],
        caregiverId: m['caregiverId'],
        caregiverName: m['caregiverName'] ?? '',
        patientId: m['patientId'] ?? '',
        patientName: m['patientName'] ?? '',
        medicationId: m['medicationId'],
        medicationName: m['medicationName'],
        missedAt: m['missedAt'] != null ? DateTime.parse(m['missedAt']) : null,
        sentAt: DateTime.parse(m['sentAt']),
        channel: NotificationChannel.values.byName(m['channel']),
        acknowledged: m['acknowledged'] ?? false,
        type: m['type'] ?? 'missedDose',
      );

  CaregiverNotification copyWith({bool? acknowledged}) => CaregiverNotification(
        id: id,
        caregiverId: caregiverId,
        caregiverName: caregiverName,
        patientId: patientId,
        patientName: patientName,
        medicationId: medicationId,
        medicationName: medicationName,
        missedAt: missedAt,
        sentAt: sentAt,
        channel: channel,
        acknowledged: acknowledged ?? this.acknowledged,
        type: type,
      );
}
