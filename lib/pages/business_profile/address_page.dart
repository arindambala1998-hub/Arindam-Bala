import 'package:flutter/material.dart';
import 'package:troonky_link/services/address_api.dart';

/// ✅ Address Selector (Checkout)
/// Production-ready features:
/// - Load saved addresses from backend
/// - Add new address (pincode validation)
/// - Edit/Delete address
/// - Select default + deliver here
///
/// Backend recommendation:
/// /addresses CRUD as implemented in AddressAPI.
class AddressPage extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddressSelected;
  final String? userId;

  const AddressPage({
    super.key,
    required this.onAddressSelected,
    this.userId,
  });

  @override
  State<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends State<AddressPage> {
  bool _loading = true;
  String _error = '';

  List<Map<String, dynamic>> _addresses = [];
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await AddressAPI.list(userId: widget.userId);
      _safeSetState(() {
        _addresses = list;
        // select default if exists
        final idx = _addresses.indexWhere((a) => a['is_default'] == true || a['default'] == true);
        _selectedIndex = idx >= 0 ? idx : (_addresses.isEmpty ? -1 : 0);
      });
    } catch (e) {
      _safeSetState(() => _error = e.toString());
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  String _s(dynamic v, {String fb = ''}) {
    final x = (v ?? '').toString().trim();
    return x.isEmpty ? fb : x;
  }

  bool _validPin(String p) {
    final s = p.trim();
    if (s.length != 6) return false;
    return int.tryParse(s) != null;
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddressFormSheet(existing: existing),
    );
    if (res == null) return;

    // Save to backend
    try {
      if ((existing?['id'] ?? existing?['_id']) != null) {
        final id = _s(existing?['id'] ?? existing?['_id']);
        await AddressAPI.update(id, res);
      } else {
        await AddressAPI.create(res);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> addr) async {
    final id = _s(addr['id'] ?? addr['_id']);
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete address?'),
        content: const Text('This address will be removed permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AddressAPI.remove(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Select Delivery Address'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Saved addresses', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _addOrEdit(),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_addresses.isEmpty)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No addresses yet. Tap Add to create one.'),
                    ),
                  )
                else
                  ...List.generate(_addresses.length, (i) {
                    final a = _addresses[i];
                    final selected = _selectedIndex == i;
                    final line1 = _s(a['line1'] ?? a['address_line1'] ?? a['address']);
                    final line2 = _s(a['line2'] ?? a['address_line2']);
                    final city = _s(a['city']);
                    final state = _s(a['state']);
                    final pin = _s(a['pincode'] ?? a['pin'] ?? a['zip']);
                    final label = _s(a['type'] ?? a['label'], fb: 'Address');
                    final badPin = pin.isNotEmpty && !_validPin(pin);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? Colors.deepPurple : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Radio<int>(
                            value: i,
                            groupValue: _selectedIndex,
                            onChanged: (v) => _safeSetState(() => _selectedIndex = v ?? -1),
                            activeColor: Colors.deepPurple,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                                    const SizedBox(width: 8),
                                    if (a['is_default'] == true || a['default'] == true)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text('DEFAULT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.green)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  [line1, if (line2.isNotEmpty) line2, '$city, $state - $pin'].where((x) => x.trim().isNotEmpty).join('\n'),
                                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                                ),
                                if (badPin)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text('Invalid PIN', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _addOrEdit(existing: a),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _delete(a),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(14),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_selectedIndex < 0 || _selectedIndex >= _addresses.length)
                      ? null
                      : () {
                    final a = _addresses[_selectedIndex];
                    final pin = _s(a['pincode'] ?? a['pin'] ?? a['zip']);
                    if (pin.isNotEmpty && !_validPin(pin)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fix the PIN code'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    widget.onAddressSelected(a);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Deliver Here', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _AddressFormSheet({this.existing});

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  late final TextEditingController _label;
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pin;

  bool _makeDefault = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const <String, dynamic>{};
    _label = TextEditingController(text: (e['type'] ?? e['label'] ?? 'Home').toString());
    _line1 = TextEditingController(text: (e['line1'] ?? e['address_line1'] ?? e['address'] ?? '').toString());
    _line2 = TextEditingController(text: (e['line2'] ?? e['address_line2'] ?? '').toString());
    _city = TextEditingController(text: (e['city'] ?? '').toString());
    _state = TextEditingController(text: (e['state'] ?? '').toString());
    _pin = TextEditingController(text: (e['pincode'] ?? e['pin'] ?? e['zip'] ?? '').toString());
    _makeDefault = (e['is_default'] == true || e['default'] == true);
  }

  @override
  void dispose() {
    _label.dispose();
    _line1.dispose();
    _line2.dispose();
    _city.dispose();
    _state.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool _validPin(String p) => p.trim().length == 6 && int.tryParse(p.trim()) != null;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(left: 14, right: 14, top: 14, bottom: bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEdit ? 'Edit Address' : 'New Address', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          _field('Label (Home/Work)', _label),
          _field('Address line 1', _line1),
          _field('Address line 2 (optional)', _line2),
          Row(
            children: [
              Expanded(child: _field('City', _city)),
              const SizedBox(width: 10),
              Expanded(child: _field('State', _state)),
            ],
          ),
          _field('PIN Code', _pin, keyboard: TextInputType.number),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _makeDefault,
            onChanged: (v) => setState(() => _makeDefault = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as default'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                final line1 = _line1.text.trim();
                final city = _city.text.trim();
                final state = _state.text.trim();
                final pin = _pin.text.trim();

                if (line1.isEmpty || city.isEmpty || state.isEmpty || pin.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
                  );
                  return;
                }
                if (!_validPin(pin)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN must be 6 digits'), backgroundColor: Colors.red),
                  );
                  return;
                }

                Navigator.pop(context, {
                  'type': _label.text.trim(),
                  'line1': line1,
                  'line2': _line2.text.trim(),
                  'city': city,
                  'state': state,
                  'pincode': pin,
                  'is_default': _makeDefault,
                });
              },
              child: Text(isEdit ? 'Save Changes' : 'Save Address'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
