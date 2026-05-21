enum NotificationChannel { sms, inApp, both }

class CaregiverNotification {
  final String id;
  final String caregiverId;
  final String caregiverName;
  final String medicationId;
  final String medicationName;
  final DateTime missedAt;
  final DateTime sentAt;
  final NotificationChannel channel;
  final bool acknowledged;

  const CaregiverNotification({
    required this.id, required this.caregiverId, required this.caregiverName,
    required this.medicationId, required this.medicationName,
    required this.missedAt, required this.sentAt,
    required this.channel, this.acknowledged = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'caregiverId': caregiverId, 'caregiverName': caregiverName,
    'medicationId': medicationId, 'medicationName': medicationName,
    'missedAt': missedAt.toIso8601String(), 'sentAt': sentAt.toIso8601String(),
    'channel': channel.name, 'acknowledged': acknowledged,
  };

  factory CaregiverNotification.fromMap(Map<String, dynamic> m) =>
      CaregiverNotification(
        id: m['id'], caregiverId: m['caregiverId'],
        caregiverName: m['caregiverName'], medicationId: m['medicationId'],
        medicationName: m['medicationName'],
        missedAt: DateTime.parse(m['missedAt']),
        sentAt: DateTime.parse(m['sentAt']),
        channel: NotificationChannel.values.byName(m['channel']),
        acknowledged: m['acknowledged'] ?? false,
      );

  CaregiverNotification copyWith({bool? acknowledged}) =>
      CaregiverNotification(
        id: id, caregiverId: caregiverId, caregiverName: caregiverName,
        medicationId: medicationId, medicationName: medicationName,
        missedAt: missedAt, sentAt: sentAt, channel: channel,
        acknowledged: acknowledged ?? this.acknowledged,
      );
}