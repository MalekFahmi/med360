part of 'firebase_backend_service.dart';

extension FirebaseBackendReportMethods on FirebaseBackendService {
  Future<void> shareReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String reportType,
    required Map<String, dynamic> report,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = currentUid;
    if (patientUid == null) {
      throw Exception('No authenticated Firebase user');
    }
    await _firestore!.collection('sharedReports').add({
      'patientId': patientId,
      'patientUid': patientUid,
      'patientName': patientName,
      'recipientRole': recipientRole,
      'recipientId': recipientId,
      'reportType': reportType,
      'report': report,
      'actorUid': patientUid,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
    });
    await logAdherenceEvent(
      patientId: patientId,
      patientUid: patientUid,
      eventType: 'reportShared',
      source: 'patient',
      details: {
        'recipientRole': recipientRole,
        'recipientId': recipientId,
        'reportType': reportType,
      },
    );
  }

  Future<void> uploadPatientReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (!_enabled || _firestore == null || _storage == null) return;
    final patientUid = currentUid;
    if (patientUid == null) {
      throw Exception('No authenticated Firebase user');
    }

    final sanitizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final storagePath =
        'patientReports/$patientUid/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
    final ref = _storage!.ref(storagePath);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType ?? _contentTypeFor(fileName),
        customMetadata: {
          'patientId': patientId,
          'patientUid': patientUid,
          'recipientRole': recipientRole,
          'recipientId': recipientId,
        },
      ),
    );
    final downloadUrl = await ref.getDownloadURL();

    await _firestore!.collection('sharedReports').add({
      'patientId': patientId,
      'patientUid': patientUid,
      'patientName': patientName,
      'recipientRole': recipientRole,
      'recipientId': recipientId,
      'reportType': 'uploaded',
      'report': {
        'label': fileName,
        'fileName': fileName,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'contentType': contentType ?? _contentTypeFor(fileName),
        'sizeBytes': bytes.lengthInBytes,
      },
      'actorUid': patientUid,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
    });

    await logAdherenceEvent(
      patientId: patientId,
      patientUid: patientUid,
      eventType: 'patientReportUploaded',
      source: 'patient',
      details: {
        'recipientRole': recipientRole,
        'recipientId': recipientId,
        'fileName': fileName,
        'storagePath': storagePath,
        'sizeBytes': bytes.lengthInBytes,
      },
    );
  }

  Future<void> logUserEngagementEvent({
    String? patientId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) async {
    if (!_enabled || _firestore == null) return;
    try {
      final role = await _currentUserRole();
      final patientUid =
          patientId == null ? null : await _patientUidForPatientId(patientId);
      await _firestore!.collection('adherenceEvents').add({
        if (patientId != null) 'patientId': patientId,
        if (patientUid != null) 'patientUid': patientUid,
        'eventType': eventType,
        'source': source,
        'eventCategory': 'userEngagement',
        'details': {if (role != null) 'actorRole': role, ...?details},
        'timestamp': FieldValue.serverTimestamp(),
        'actorUid': currentUid,
      });
    } catch (e) {
      debugPrint('User engagement event skipped ($eventType): $e');
    }
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  Future<List<Map<String, dynamic>>> fetchSharedReportsForRecipient({
    required String recipientId,
    String? recipientRole,
  }) async {
    if (!_enabled || _firestore == null) return const [];
    final snap = await _firestore!
        .collection('sharedReports')
        .where('recipientId', isEqualTo: recipientId)
        .get();
    final reports = snap.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .where((report) =>
            recipientRole == null || report['recipientRole'] == recipientRole)
        .toList();
    reports.sort((a, b) {
      final aDate = _dateFromAny(a['createdAt']) ?? DateTime(1970);
      final bDate = _dateFromAny(b['createdAt']) ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return reports;
  }

  Future<List<Map<String, dynamic>>> fetchDoctorInbox(String doctorUid) async {
    if (!_enabled || _firestore == null) return const [];
    final snap = await _firestore!
        .collection('doctorInboxes')
        .doc(doctorUid)
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> markReportReviewed(String reportId) async {
    if (!_enabled || _firestore == null) return;
    final reportDoc =
        await _firestore!.collection('sharedReports').doc(reportId).get();
    final report = reportDoc.data();
    await _firestore!.collection('sharedReports').doc(reportId).set({
      'reviewedAt': FieldValue.serverTimestamp(),
      'archived': false,
    }, SetOptions(merge: true));
    if (report != null) {
      final role =
          await _currentUserRole() ?? report['recipientRole'] ?? 'user';
      await logAdherenceEvent(
        patientId: report['patientId'] ?? '',
        patientUid: report['patientUid'],
        eventType: role == 'doctor'
            ? 'doctorReportReviewed'
            : role == 'caregiver'
                ? 'caregiverReportReviewed'
                : 'reportReviewed',
        source: role,
        details: {'reportId': reportId, 'reportType': report['reportType']},
      );
    }
  }

  Future<void> archiveReport(String reportId) async {
    if (!_enabled || _firestore == null) return;
    final reportDoc =
        await _firestore!.collection('sharedReports').doc(reportId).get();
    final report = reportDoc.data();
    await _firestore!.collection('sharedReports').doc(reportId).set({
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (report != null) {
      final role =
          await _currentUserRole() ?? report['recipientRole'] ?? 'user';
      await logAdherenceEvent(
        patientId: report['patientId'] ?? '',
        patientUid: report['patientUid'],
        eventType: role == 'doctor'
            ? 'doctorReportArchived'
            : role == 'caregiver'
                ? 'caregiverReportArchived'
                : 'reportArchived',
        source: role,
        details: {'reportId': reportId, 'reportType': report['reportType']},
      );
    }
  }

  Future<void> restoreReport(String reportId) async {
    if (!_enabled || _firestore == null) return;
    final reportDoc =
        await _firestore!.collection('sharedReports').doc(reportId).get();
    final report = reportDoc.data();
    await _firestore!.collection('sharedReports').doc(reportId).set({
      'archived': false,
      'restoredAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (report != null) {
      final role =
          await _currentUserRole() ?? report['recipientRole'] ?? 'user';
      await logAdherenceEvent(
        patientId: report['patientId'] ?? '',
        patientUid: report['patientUid'],
        eventType: role == 'doctor'
            ? 'doctorReportRestored'
            : role == 'caregiver'
                ? 'caregiverReportRestored'
                : 'reportRestored',
        source: role,
        details: {'reportId': reportId, 'reportType': report['reportType']},
      );
    }
  }
}
