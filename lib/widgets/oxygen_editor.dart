import 'package:flutter/material.dart';

import '../models/lab_set.dart';
import '../services/clinical_calc.dart';
import '../theme.dart';

const oxygenDevices = ['室内気', '鼻カヌラ', '簡易マスク', 'リザーバーマスク', 'ベンチュリーマスク', 'ハイフロー', 'NPPV', '人工呼吸器'];

/// 酸素投与の表示・手入力欄。
class OxygenEditor extends StatefulWidget {
  const OxygenEditor({super.key, required this.oxygen, required this.onChanged});
  final OxygenInfo oxygen;
  final VoidCallback onChanged;

  @override
  State<OxygenEditor> createState() => _OxygenEditorState();
}

class _OxygenEditorState extends State<OxygenEditor> {
  late final TextEditingController _flow;
  late final TextEditingController _fio2;

  @override
  void initState() {
    super.initState();
    _flow = TextEditingController(text: widget.oxygen.flowLpm?.toString() ?? '');
    _fio2 = TextEditingController(
        text: widget.oxygen.fio2 == null ? '' : (widget.oxygen.fio2! * 100).toStringAsFixed(0));
  }

  @override
  void dispose() {
    _flow.dispose();
    _fio2.dispose();
    super.dispose();
  }

  void _changed() {
    widget.oxygen.manual = true;
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oxygen;
    final scheme = Theme.of(context).colorScheme;
    final f = resolveFio2(o);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (o.foundTexts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              Text('用紙の記載:', style: TextStyle(color: scheme.onSurfaceVariant)),
              for (final t in o.foundTexts) Chip(label: Text(t), visualDensity: VisualDensity.compact),
            ]),
          )
        else if (!o.manual)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: context.lab.uncertainBg,
              border: Border.all(color: context.lab.uncertainBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.help_outline, size: 18),
              SizedBox(width: 6),
              Expanded(child: Text('酸素投与の記載なし（未確認）。必要に応じて入力してください。')),
            ]),
          ),
        Row(children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: oxygenDevices.contains(o.device) ? o.device : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '投与方法'),
              items: [
                const DropdownMenuItem(value: null, child: Text('未選択')),
                for (final d in oxygenDevices) DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) {
                o.device = v;
                if (v == '室内気') {
                  o.fio2 = 0.21;
                  o.flowLpm = null;
                  _fio2.text = '21';
                  _flow.text = '';
                }
                _changed();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _flow,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '流量', suffixText: 'L/分'),
              onChanged: (v) {
                o.flowLpm = double.tryParse(v);
                _changed();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _fio2,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'FiO₂', suffixText: '%'),
              onChanged: (v) {
                final x = double.tryParse(v);
                o.fio2 = x == null ? null : (x > 1 ? x / 100 : x);
                if (o.fio2 != null && (o.fio2! < 0.21 || o.fio2! > 1)) o.fio2 = null;
                _changed();
              },
            ),
          ),
        ]),
        if (o.fio2 == null && f.fio2 != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('器具と流量からの推定 FiO₂ ≈ ${(f.fio2! * 100).toStringAsFixed(0)}%（目安）',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}
