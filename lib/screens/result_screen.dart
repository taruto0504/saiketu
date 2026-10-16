import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/clinical_calc.dart';
import '../services/lab_catalog.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/oxygen_editor.dart';
import '../widgets/pickers.dart';
import 'ai_screen.dart';
import 'compare_screen.dart';
import 'diagnosis_screen.dart';

/// 結果画面（上部に危険値・A/V推定・酸素投与、下に全項目）。
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.set});
  final LabSet set;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  LabSet get set => widget.set;
  LabSet? _previous;
  int _folderCount = 0;
  late bool _abnormalOnly = context.read<AppSettings>().abnormalOnly;
  DiagnosisController? _diag;
  bool _prevLoaded = false;

  @override
  void initState() {
    super.initState();
    context.read<AppSettings>().stats.track('result_view');
    _loadPrevious();
  }

  @override
  void dispose() {
    _diag?.dispose();
    super.dispose();
  }

  Future<void> _loadPrevious() async {
    final services = context.read<AppServices>();
    if (!set.isSaved) {
      _prevLoaded = true;
      return;
    }
    final prev = await services.db.previousOf(set);
    final all = await services.db.labSets(set.folderId!);
    if (!mounted) return;
    setState(() {
      _previous = prev;
      _folderCount = all.length;
      _prevLoaded = true;
    });
  }

  Future<void> _persist() async {
    setState(() {});
    if (set.isSaved) {
      final services = context.read<AppServices>();
      await services.db.saveLabSet(set);
      services.dataChanged();
    }
  }

  Future<void> _save() async {
    final f = await showFolderPicker(context);
    if (f == null || !mounted) return;
    final services = context.read<AppServices>();
    set.folderId = f.id;
    await services.db.saveLabSet(set);
    services.dataChanged();
    if (!mounted) return;
    showSnack(context, '「${f.name}」に保存しました');
    await _loadPrevious();
  }

  DiagnosisController _diagController() {
    return _diag ??= DiagnosisController(context.read<AppServices>(), set, _previous)..init();
  }

  void _openDiagnosis() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => DiagnosisScreen(set: set, previous: _previous)));

  void _openAi() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => AiScreen(set: set, previous: _previous)));

  void _openCompare() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => CompareScreen(folderId: set.folderId!, currentId: set.id)));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 840;
    final results = _ResultsList(
      set: set,
      previous: _previous,
      abnormalOnly: _abnormalOnly,
      onChanged: _persist,
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('結果'),
          Text('採血 ${dateTimeFmt.format(set.takenAt)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          if (!set.isSaved)
            TextButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SwitchListTile(
              dense: true,
              title: const Text('異常値のみ表示'),
              secondary: const Icon(Icons.filter_alt_outlined),
              value: _abnormalOnly,
              onChanged: (v) => setState(() => _abnormalOnly = v),
            ),
          ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: results),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: !_prevLoaded
                            ? const Center(child: CircularProgressIndicator())
                            : ChangeNotifierProvider<DiagnosisController>.value(
                          value: _diagController(),
                          child: Builder(builder: (context) {
                            final c = context.watch<DiagnosisController>();
                            return Column(children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                child: Row(children: [
                                  const Expanded(
                                      child: Text('疾患推定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                                  TextButton.icon(
                                    onPressed: () => c.evaluate(useContext: !c.set.context.isEmpty),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('最新値で再評価'),
                                  ),
                                ]),
                              ),
                              const Expanded(child: DiagnosisPanel(embedded: true)),
                            ]);
                          }),
                        ),
                      ),
                    ],
                  )
                : results,
          ),
        ],
      ),
      bottomNavigationBar: BottomActions(children: [
        if (wide)
          FilledButton.icon(
            onPressed: _prevLoaded ? () => _diagController().addContextAndReevaluate(context) : null,
            icon: const Icon(Icons.playlist_add),
            label: const Text('情報を追加して再評価'),
          )
        else
          FilledButton.icon(onPressed: _openDiagnosis, icon: const Icon(Icons.manage_search), label: const Text('疾患推定')),
        OutlinedButton.icon(onPressed: _openAi, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('AI')),
        if (set.isSaved && _folderCount >= 2)
          OutlinedButton.icon(onPressed: _openCompare, icon: const Icon(Icons.compare_arrows), label: const Text('比較')),
      ]),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.set, required this.previous, required this.abnormalOnly, required this.onChanged});
  final LabSet set;
  final LabSet? previous;
  final bool abnormalOnly;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final services = context.read<AppServices>();
    final sex = set.context.sex;
    final spec = effectiveSpecimen(set);
    final est = estimateSpecimen(set);
    final lab = context.lab;
    final scheme = Theme.of(context).colorScheme;

    final entries = [
      for (final v in set.values)
        if (v.value != null) (v: v, def: catalog.byCode(v.code), flag: catalog.flagFor(v, sex: sex, specimen: spec)),
    ];
    final critical = entries.where((e) => e.flag.isCritical).toList();
    final abnormal = entries.where((e) => e.flag.isAbnormal).length;
    final sampleWarnings = services.engine.evaluate(set, previous: previous).sampleWarnings;
    final derived = computeDerived(set);
    final gas = hasBloodGas(set.valueMap);
    final prev = previous?.valueMap ?? const {};

    final byCat = <LabCategory, List<({LabValue v, LabItemDef? def, LabFlag flag})>>{};
    for (final e in entries) {
      if (abnormalOnly && !e.flag.isAbnormal) continue;
      byCat.putIfAbsent(e.def?.category ?? LabCategory.custom, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // ── 危険値 ──
        if (critical.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: lab.critBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: lab.critFg, width: 2),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_rounded, color: lab.critFg),
                const SizedBox(width: 6),
                Text('危険値 ${critical.length}項目', style: TextStyle(color: lab.critFg, fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
              const SizedBox(height: 6),
              for (final e in critical)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(e.def?.name ?? e.v.code,
                          style: TextStyle(color: lab.critFg, fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    Text(formatNumber(e.v.value!, e.def?.decimals ?? 1),
                        style: numberStyle(context, size: 24, color: lab.critFg)),
                    Icon(e.flag.isHigh ? Icons.arrow_upward : Icons.arrow_downward, color: lab.critFg,
                        semanticLabel: e.flag.isHigh ? '高値' : '低値'),
                    const SizedBox(width: 4),
                    SizedBox(width: 70, child: Text(e.def?.unit ?? '', style: TextStyle(color: lab.critFg, fontSize: 12))),
                  ]),
                ),
            ]),
          ),
        // ── 検体エラー ──
        for (final w in sampleWarnings) SampleWarningCard(w),
        // ── A/V 推定 ──
        if (gas)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.bloodtype_outlined, color: scheme.primary),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('血液ガス 検体の推定', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  Text(
                    est.type == SpecimenType.unknown ? '判別困難' : '${est.type.label}(${est.type.short})',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: scheme.primary),
                  ),
                ]),
                const SizedBox(height: 4),
                for (final r in est.reasons) Text('・$r', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  est.fromSheet || est.manual ? '基準値・評価は${spec.label}として表示しています。' : 'あくまで推定です。基準値・評価は${spec.label}として表示しています。',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                SegmentedButton<SpecimenType?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('自動')),
                    ButtonSegment(value: SpecimenType.arterial, label: Text('動脈血')),
                    ButtonSegment(value: SpecimenType.venous, label: Text('静脈血')),
                  ],
                  selected: {set.specimen.manual},
                  onSelectionChanged: (s) {
                    set.specimen.manual = s.first;
                    onChanged();
                  },
                ),
              ]),
            ),
          ),
        // ── 酸素投与 ──
        Card(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.air, color: scheme.primary),
              title: const Text('酸素投与', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_oxygenSummary(set.oxygen, derived)),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [OxygenEditor(oxygen: set.oxygen, onChanged: onChanged)],
            ),
          ),
        ),
        // ── 全項目 ──
        SectionHeader('検査値（${entries.length}項目・異常 $abnormal）', icon: Icons.list_alt),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            child: const Row(children: [
              Expanded(flex: 5, child: Text('項目名')),
              Expanded(flex: 5, child: Text('測定値', textAlign: TextAlign.right)),
              SizedBox(width: 10),
              Expanded(flex: 5, child: Text('基準値')),
              Expanded(flex: 4, child: Text('単位')),
            ]),
          ),
        ),
        if (byCat.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('異常値はありません')),
        for (final cat in LabCategory.values)
          if (byCat[cat] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(cat.label, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
            ),
            for (final e in byCat[cat]!)
              _ValueRow(
                v: e.v,
                def: e.def,
                flag: e.flag,
                range: catalog.rangeFor(e.v, sex: sex, specimen: spec),
                prev: prev[e.v.code],
              ),
          ],
        if (derived.isNotEmpty) ...[
          const SectionHeader('計算値', icon: Icons.functions),
          for (final d in derived.values)
            ListTile(
              dense: true,
              title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text([d.formula, if (d.note != null) d.note!].join('\n')),
              trailing: Text('${formatNumber(d.value, d.decimals)} ${d.unit}', style: numberStyle(context, size: 18)),
            ),
        ],
        const DisclaimerFooter(),
      ],
    );
  }

  String _oxygenSummary(OxygenInfo o, Map<String, DerivedValue> derived) {
    final parts = <String>[];
    if (o.device != null) parts.add(o.device!);
    if (o.flowLpm != null) parts.add('${o.flowLpm}L/分');
    if (o.fio2 != null) parts.add('FiO2 ${(o.fio2! * 100).toStringAsFixed(0)}%');
    final pf = derived['PF'];
    if (pf != null) parts.add('${pf.label} ${pf.value.toStringAsFixed(0)}');
    if (parts.isEmpty) return '酸素投与の記載なし（未確認）・タップして入力';
    return '${parts.join('・')}${o.manual ? '（入力）' : '（用紙の記載）'}';
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.v, required this.def, required this.flag, required this.range, this.prev});
  final LabValue v;
  final LabItemDef? def;
  final LabFlag flag;
  final RefRange range;
  final double? prev;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final scheme = Theme.of(context).colorScheme;
    final color = flag.isHigh ? lab.high : (flag.isLow ? lab.low : scheme.onSurface);
    final dec = def?.decimals ?? 1;
    return Semantics(
      label: '${def?.name ?? v.code} ${formatNumber(v.value!, dec)} ${def?.unit ?? ''} '
          '${flag.isHigh ? '高値' : flag.isLow ? '低値' : ''}${flag.isCritical ? ' 危険値' : ''}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: flag.isCritical ? lab.critBg : null,
          borderRadius: BorderRadius.circular(8),
          border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(def?.name ?? v.code, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: flag.isCritical ? lab.critFg : null)),
                if (prev != null)
                  Text('前回 ${formatNumber(prev!, dec)}', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ]),
            ),
            Expanded(
              flex: 5,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatNumber(v.value!, dec), style: numberStyle(context, size: 23, color: color)),
                  ),
                ),
                SizedBox(
                  width: 22,
                  child: flag.isAbnormal
                      ? Icon(flag.isHigh ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: color)
                      : null,
                ),
              ]),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(range.format(dec), style: const TextStyle(fontSize: 13.5, fontFeatures: [FontFeature.tabularFigures()])),
                if (range.source != RefSource.defaults)
                  Text(range.source.label, style: TextStyle(fontSize: 10.5, color: scheme.primary)),
              ]),
            ),
            Expanded(flex: 4, child: Text(def?.unit ?? v.unit, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
          ],
        ),
      ),
    );
  }
}
