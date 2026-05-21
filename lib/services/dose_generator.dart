// Generates DoseConfirmation records for a given date based on the
// patient's active medications. Called every day on app open.

import '../models/models.dart';

class DoseGenerator {
  /// For each active medication, check if a dose for [date] already exists
  /// in [existingDoses]. If not, create a pending one.
  static List<DoseConfirmation> generateForDate({
    required List<Medication> medications,
    required List<DoseConfirmation> existingDoses,
    required DateTime date,
  }) {
    final newDoses = <DoseConfirmation>[];

    for (final med in medications) {
      if (med.status != MedicationStatus.active) continue;
      if (date.isBefore(med.startDate.subtract(const Duration(days: 1)))) continue;

      for (final time in med.reminderTimes) {
        final timeStr = time.display;
        // Check if this dose already exists
        final exists = existingDoses.any((d) =>
            d.medicationId == med.id &&
            d.scheduledTime == timeStr &&
            d.isOnDate(date));

        if (!exists) {
          newDoses.add(DoseConfirmation(
            id: '${med.id}-${_dateKey(date)}-$timeStr',
            medicationId: med.id,
            medicationName: med.displayName,
            scheduledTime: timeStr,
            scheduledDate: DateTime(date.year, date.month, date.day),
            status: DoseStatus.pending,
          ));
        }
      }
    }
    return newDoses;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
}