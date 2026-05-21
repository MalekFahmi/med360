import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class AddMedicationScreen extends StatefulWidget {
  final Medication? medication;
  const AddMedicationScreen({super.key, this.medication});
  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _dosageCtrl;
  List<ReminderTime> _times = [const ReminderTime(hour: 8, minute: 0)];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.medication?.name);
    _dosageCtrl = TextEditingController(text: widget.medication?.dosage);
    if (widget.medication != null) {
      _times = List.from(widget.medication!.reminderTimes);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AuthProvider>().arabicMode;
    return Scaffold(
      appBar: AppBar(title: Text(isAr ? 'إضافة دواء' : 'Add Medication')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: isAr ? 'الاسم' : 'Name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _dosageCtrl,
              decoration: InputDecoration(labelText: isAr ? 'الجرعة' : 'Dosage'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            ..._times.asMap().entries.map((e) => ListTile(
                  title: Text(e.value.display),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => setState(() => _times.removeAt(e.key)),
                  ),
                )),
            TextButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (t != null) {
                  setState(() => _times.add(ReminderTime(hour: t.hour, minute: t.minute)));
                }
              },
              child: Text(isAr ? 'إضافة موعد' : 'Add Time'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final auth = context.read<AuthProvider>();
                final meds = context.read<MedicationProvider>();
                final med = Medication(
                  id: widget.medication?.id ?? 'MED-${DateTime.now().millisecondsSinceEpoch}',
                  name: _nameCtrl.text,
                  nameAr: _nameCtrl.text,
                  dosage: _dosageCtrl.text,
                  form: MedicationForm.tablet,
                  indication: '',
                  indicationAr: '',
                  reminderTimes: _times,
                  reminderType: ReminderType.notification,
                  status: MedicationStatus.active,
                  startDate: DateTime.now(),
                );
                if (widget.medication == null) {
                  await meds.addMedication(auth.patient!.id, med);
                } else {
                  await meds.updateMedication(auth.patient!.id, med);
                }
                if (mounted) Navigator.pop(context);
              },
              child: Text(isAr ? 'حفظ' : 'Save'),
            )
          ],
        ),
      ),
    );
  }
}
