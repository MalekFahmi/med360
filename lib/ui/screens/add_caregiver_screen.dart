import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class AddCaregiverScreen extends StatefulWidget {
  const AddCaregiverScreen({super.key});
  @override
  State<AddCaregiverScreen> createState() => _AddCaregiverScreenState();
}

class _AddCaregiverScreenState extends State<AddCaregiverScreen> {
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _r = TextEditingController();

  @override
  void dispose() {
    _n.dispose();
    _p.dispose();
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AuthProvider>().arabicMode;
    return Scaffold(
      appBar: AppBar(title: Text(isAr ? 'إضافة مرافق' : 'Add Caregiver')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _n, decoration: InputDecoration(labelText: isAr ? 'الاسم' : 'Name')),
          TextField(controller: _p, decoration: InputDecoration(labelText: isAr ? 'الهاتف' : 'Phone')),
          TextField(controller: _r, decoration: InputDecoration(labelText: isAr ? 'العلاقة' : 'Relation')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              await auth.addCaregiver(Caregiver(
                id: 'CG-${DateTime.now().millisecondsSinceEpoch}',
                name: _n.text,
                phone: _p.text,
                relationship: _r.text,
                permission: NotificationPermission.all,
              ));
              if (mounted) Navigator.pop(context);
            },
            child: Text(isAr ? 'حفظ' : 'Save'),
          )
        ],
      ),
    );
  }
}
