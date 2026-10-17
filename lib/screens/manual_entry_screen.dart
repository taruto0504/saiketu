import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/lab_catalog.dart';
import '../services/settings.dart';
import '../widgets/common.dart';
import 'confirm_screen.dart';

/// 手入力画面（全項目をカテゴリ別に表示）。
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, this.folderId});
  final String? folderId;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final Map<String, TextEditingController> _c = {};
  String _q = '';

  TextEditingController _ctrl(String code) => _c.putIfAbsent(code, TextEditingController.new);

  int get _filled => _c.values.where((c) => c.text.trim().isNotEmpty).length;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() {
    final catalog = context.read<LabCatalog>();
    final values = <LabValue>[];
    for (final def in catalog.all) {
      final t = _c[def.code]?.text.trim() ?? '';
      if (t.isEmpty) continue;
      final x = double.tryParse(t.replaceAll(',', '.'));
      final v = LabValue(code: def.code, value: x, unit: def.unit);
      if (x == null) {
        v.uncertain = true;
        v.warnings.add('数値として認識できません');
      } else {
        final issue = catalog.checkPlausibility(def.code, x);
        if (issue != null) {
          v.uncertain = true;
          v.warnings.add(issue.message);
        }
      }
      values.add(v);
    }
    if (values.isEmpty) {
      showSnack(context, '1項目以上入力してください');
      return;
    }
    context.read<AppSettings>().stats.track('read_manual');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmScreen(
          set: LabSet(values: values, source: 'manual'),
          targetFolderId: widget.folderId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final q = normalizeName(_q);
    bool match(LabItemDef i) =>
        q.isEmpty || [i.code, i.name, i.jpName, ...i.aliases].any((a) => normalizeName(a).contains(q));
    return Scaffold(
      appBar: AppBar(title: const Text('手入力')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '項目を検索（例: Cr, 血糖, PT-INR）'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final cat in LabCategory.values)
                  if (catalog.byCategory(cat).any(match))
                    ExpansionTile(
                      key: PageStorageKey('cat_${cat.name}_$q'),
                      initiallyExpanded: q.isNotEmpty || cat == LabCategory.cbc || cat == LabCategory.renal,
                      title: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${catalog.byCategory(cat).where((i) => (_c[i.code]?.text.trim() ?? '').isNotEmpty).length} 項目入力済み'),
                      children: [
                        for (final def in catalog.byCategory(cat).where(match)) _row(def),
                      ],
                    ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActions(children: [
        FilledButton(onPressed: _next, child: Text('確認へ（$_filled項目）')),
      ]),
    );
  }

  Widget _row(LabItemDef def) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(def.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(def.jpName, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
            ]),
          ),
          Expanded(
            flex: 3,
            child: def.isQualitative
                ? DropdownButtonFormField<double>(
                    initialValue: double.tryParse(_ctrl(def.code).text),
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, hintText: '—'),
                    items: [for (final o in def.ordinals) DropdownMenuItem(value: o.value, child: Text(o.label))],
                    onChanged: (x) => setState(() => _ctrl(def.code).text = x?.toString() ?? ''),
                  )
                : TextField(
              controller: _ctrl(def.code),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()]),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 72, child: Text(def.unit, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}
