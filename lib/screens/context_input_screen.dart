import 'package:flutter/material.dart';

import '../models/lab_set.dart';
import '../widgets/common.dart';

const symptomChoices = [
  '発熱', '悪寒', '倦怠感', '食欲不振', '嘔気', '嘔吐', '下痢', '腹痛', '心窩部痛', '右季肋部痛', '背部痛',
  '胸痛', '動悸', '呼吸困難', '咳', '痰', '浮腫', '尿量減少', '吐血', '黒色便', '下血', '黄疸',
  '意識障害', '頭痛', '痙攣', 'しびれ', '脱力', '失神', '口渇', '体重減少', '筋肉痛', '褐色尿', '下肢腫脹', '紫斑',
];

/// 第2段階：追加情報の入力（すべて任意）。
class ContextInputScreen extends StatefulWidget {
  const ContextInputScreen({super.key, required this.initial});
  final PatientContext initial;

  @override
  State<ContextInputScreen> createState() => _ContextInputScreenState();
}

class _ContextInputScreenState extends State<ContextInputScreen> {
  late final PatientContext c = widget.initial.copy();
  late final _age = TextEditingController(text: c.age?.toString() ?? '');
  late final _weight = TextEditingController(text: c.weightKg?.toString() ?? '');
  late final _temp = TextEditingController(text: c.temp?.toString() ?? '');
  late final _sbp = TextEditingController(text: c.sbp?.toString() ?? '');
  late final _dbp = TextEditingController(text: c.dbp?.toString() ?? '');
  late final _hr = TextEditingController(text: c.hr?.toString() ?? '');
  late final _rr = TextEditingController(text: c.rr?.toString() ?? '');
  late final _spo2 = TextEditingController(text: c.spo2?.toString() ?? '');
  late final _gcs = TextEditingController(text: c.gcs?.toString() ?? '');
  late final _complaint = TextEditingController(text: c.complaint);
  late final _history = TextEditingController(text: c.history);
  late final _meds = TextEditingController(text: c.medications);
  late final _course = TextEditingController(text: c.course);
  late final _other = TextEditingController(text: c.otherTests);

  static const jcsChoices = ['0', '1', '2', '3', '10', '20', '30', '100', '200', '300'];

  PatientContext _collect() {
    int? i(TextEditingController t) => int.tryParse(t.text.trim());
    double? d(TextEditingController t) => double.tryParse(t.text.trim());
    c
      ..age = i(_age)
      ..weightKg = d(_weight)
      ..temp = d(_temp)
      ..sbp = i(_sbp)
      ..dbp = i(_dbp)
      ..hr = i(_hr)
      ..rr = i(_rr)
      ..spo2 = i(_spo2)
      ..gcs = i(_gcs)
      ..complaint = _complaint.text.trim()
      ..history = _history.text.trim()
      ..medications = _meds.text.trim()
      ..course = _course.text.trim()
      ..otherTests = _other.text.trim();
    if (c.gcs != null && (c.gcs! < 3 || c.gcs! > 15)) c.gcs = null;
    return c;
  }

  Widget _num(String label, TextEditingController t, {String? suffix, bool decimal = false}) => SizedBox(
        width: 150,
        child: TextField(
          controller: t,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          style: const TextStyle(fontSize: 18),
        ),
      );

  Widget _text(String label, TextEditingController t, String hint) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: TextField(
          controller: t,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('情報を追加')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('入力はすべて任意です。1項目だけ追加して再評価することもできます。氏名などの個人情報は入力しないでください。'),
          ),
          const SectionHeader('基本情報', icon: Icons.person_outline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _num('年齢', _age, suffix: '歳'),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('性別不明')),
                  ButtonSegment(value: 'M', label: Text('男性')),
                  ButtonSegment(value: 'F', label: Text('女性')),
                ],
                selected: {c.sex},
                onSelectionChanged: (s) => setState(() => c.sex = s.first),
              ),
              _num('体重', _weight, suffix: 'kg', decimal: true),
            ]),
          ),
          const SectionHeader('バイタルサイン', icon: Icons.monitor_heart_outlined),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _num('体温', _temp, suffix: '℃', decimal: true),
              _num('収縮期血圧', _sbp, suffix: 'mmHg'),
              _num('拡張期血圧', _dbp, suffix: 'mmHg'),
              _num('脈拍', _hr, suffix: '/分'),
              _num('呼吸数', _rr, suffix: '/分'),
              _num('SpO₂', _spo2, suffix: '%'),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  initialValue: jcsChoices.contains(c.jcs) ? c.jcs : null,
                  decoration: const InputDecoration(labelText: 'JCS'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('未入力')),
                    for (final j in jcsChoices) DropdownMenuItem(value: j, child: Text(j)),
                  ],
                  onChanged: (v) => setState(() => c.jcs = v),
                ),
              ),
              _num('GCS（3–15）', _gcs),
            ]),
          ),
          const SectionHeader('主訴・症状', icon: Icons.sick_outlined),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in symptomChoices)
                FilterChip(
                  label: Text(s),
                  selected: c.symptoms.contains(s),
                  onSelected: (v) => setState(() => v ? c.symptoms.add(s) : c.symptoms.remove(s)),
                ),
            ]),
          ),
          _text('主訴・症状（自由記載）', _complaint, '例: 2日前からの心窩部痛と嘔吐'),
          const SectionHeader('背景', icon: Icons.history_edu_outlined),
          _text('既往歴', _history, '例: 糖尿病、CKD、肝硬変、COPD'),
          _text('内服薬', _meds, '例: ワルファリン、利尿薬、ARB、SGLT2阻害薬'),
          _text('経過', _course, '例: 経管栄養を再開して3日目'),
          _text('その他の検査所見', _other, '例: 胸部X線で両側すりガラス影、尿検査で潜血陽性'),
        ],
      ),
      bottomNavigationBar: BottomActions(children: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _collect()),
          icon: const Icon(Icons.refresh),
          label: const Text('この情報で再評価'),
        ),
      ]),
    );
  }
}
