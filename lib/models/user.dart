enum NotificationPermission { missedDoseOnly, all, none }

class Caregiver {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final NotificationPermission permission;

  const Caregiver({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.permission,
  });

  String get initials {
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.substring(0, 2).toUpperCase();
  }

  bool get receivesAlerts => permission != NotificationPermission.none;

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'phone': phone,
    'relationship': relationship, 'permission': permission.name,
  };

  factory Caregiver.fromMap(Map<String, dynamic> m) => Caregiver(
    id: m['id'], name: m['name'], phone: m['phone'],
    relationship: m['relationship'],
    permission: NotificationPermission.values.byName(m['permission']),
  );

  Caregiver copyWith({NotificationPermission? permission}) => Caregiver(
    id: id, name: name, phone: phone, relationship: relationship,
    permission: permission ?? this.permission,
  );
}

class PatientUser {
  final String id;
  final String name;
  final String phone;
  final String passwordHash;   // stored locally — hashed in Step 5
  final DateTime? dateOfBirth;
  final String? chronicCondition;
  final List<Caregiver> caregivers;
  final bool arabicMode;
  final bool largeFonts;
  final bool highContrast;
  final bool caregiverAlertsEnabled;
  final DateTime createdAt;

  const PatientUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.passwordHash,
    this.dateOfBirth,
    this.chronicCondition,
    required this.caregivers,
    this.arabicMode = false,
    this.largeFonts = false,
    this.highContrast = false,
    this.caregiverAlertsEnabled = true,
    required this.createdAt,
  });

  String get initials {
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.substring(0, 2).toUpperCase();
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'phone': phone, 'passwordHash': passwordHash,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'chronicCondition': chronicCondition,
    'caregivers': caregivers.map((c) => c.toMap()).toList(),
    'arabicMode': arabicMode, 'largeFonts': largeFonts,
    'highContrast': highContrast,
    'caregiverAlertsEnabled': caregiverAlertsEnabled,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PatientUser.fromMap(Map<String, dynamic> m) => PatientUser(
    id: m['id'], name: m['name'], phone: m['phone'],
    passwordHash: m['passwordHash'] ?? '',
    dateOfBirth: m['dateOfBirth'] != null ? DateTime.parse(m['dateOfBirth']) : null,
    chronicCondition: m['chronicCondition'],
    caregivers: (m['caregivers'] as List? ?? [])
        .map((c) => Caregiver.fromMap(c)).toList(),
    arabicMode: m['arabicMode'] ?? false,
    largeFonts: m['largeFonts'] ?? false,
    highContrast: m['highContrast'] ?? false,
    caregiverAlertsEnabled: m['caregiverAlertsEnabled'] ?? true,
    createdAt: DateTime.parse(m['createdAt']),
  );

  PatientUser copyWith({
    String? name, String? phone, DateTime? dateOfBirth,
    String? chronicCondition, List<Caregiver>? caregivers,
    bool? arabicMode, bool? largeFonts, bool? highContrast,
    bool? caregiverAlertsEnabled,
  }) =>
      PatientUser(
        id: id, passwordHash: passwordHash, createdAt: createdAt,
        name: name ?? this.name, phone: phone ?? this.phone,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        chronicCondition: chronicCondition ?? this.chronicCondition,
        caregivers: caregivers ?? this.caregivers,
        arabicMode: arabicMode ?? this.arabicMode,
        largeFonts: largeFonts ?? this.largeFonts,
        highContrast: highContrast ?? this.highContrast,
        caregiverAlertsEnabled: caregiverAlertsEnabled ?? this.caregiverAlertsEnabled,
      );
}