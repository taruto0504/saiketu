import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/clinical_calc.dart';
import '../services/lab_catalog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/oxygen_editor.dart';
import '../widgets/pickers.dart';
import 'result_screen.dart';

/// 読み取り（入力）結果の確認・修正画面。
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.set,
    this.targetFolderId,
    this.fromOcr = false,
    this.skippedPersonalRows = 0,
    this.pageCount = 1,
    this.failedPages = const [],
  });

  final LabSet set;
  final String? targetFolderId;
  final bool fromOcr;
  final int skippedPersonalRows;

  /// 読み取ったページ数と、読み取れなかったページ（1始まり）。
  final int pageCount;
  final List<int> failedPages;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  LabSet get set => widget.set;

  int get _uncertainCount => set.values.where((v) => v.uncertain).length;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: set.takenAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(set.takenAt));
    setState(() => set.takenAt = DateTime(d.year, d.month, d.day, t?.hour ?? set.takenAt.hour, t?.minute ?? set.takenAt.minute));
  }

  Future<void> _addItem() async {
    final it = await showItemPicker(context, exclude: set.values.map((v) => v.code).toSet());
    if (it == null) return;
    setState(() => set.values.add(LabValue(code: it.code, unit: it.unit)));
  }

  // まず結果を見せて、保存するかどうかは結果の画面で決める
  Future<void> _finish() async {
    final missing = set.values.where((v) => v.value == null).toList();
    if (missing.isNotEmpty) {
      set.values.removeWhere((v) => v.value == null);
    }
    if (set.values.isEmpty) {
      showSnack(context, '検査値が1つもありません。項目を追加してください。');
      return;
    }
    if (_uncertainCount > 0) {
      final ok = await confirmDialog(context,
          title: '未確認の項目があります',
          message: '黄色の項目（$_uncertainCount件）は読み取りが不確かです。原本と照合しましたか？',
          ok: 'このまま進む',
          destructive: false);
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(set: set, saveTo: widget.targetFolderId)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final hasGas = hasBloodGas(set.valueMap) || set.values.any((v) => catalog.byCode(v.code)?.isGas ?? false);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.fromOcr ? '読み取り結果の確認' : '入力内容の確認')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _uncertainCount > 0 ? context.lab.uncertainBg : context.lab.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _uncertainCount > 0 ? context.lab.uncertainBorder : scheme.outlineVariant),
            ),
            child: Row(children: [
              Icon(_uncertainCount > 0 ? Icons.warning_amber_rounded : Icons.fact_check_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fromOcr
                      ? (_uncertainCount > 0
                          ? '原本と照合してください。黄色の $_uncertainCount 項目は読み取りが不確かです。'
                          : '原本と照合し、誤りがあれば修正してください。')
                      : '入力内容を確認してください。',
                ),
              ),
            ]),
          ),
          if (widget.pageCount > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${widget.pageCount}ページを読み取り、1つにまとめました。'
                '${widget.failedPages.isEmpty ? '' : '${widget.failedPages.join('・')}ページ目は読み取れませんでした（撮り直すか、手で追加してください）。'}',
                style: TextStyle(fontSize: 13, color: widget.failedPages.isEmpty ? scheme.onSurfaceVariant : scheme.error),
              ),
            ),
          if (widget.skippedPersonalRows > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('氏名・ID等を含む ${widget.skippedPersonalRows} 行は読み取り対象から除外しました（保存されません）。',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          if (widget.fromOcr && set.values.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('検査項目を読み取れませんでした。明るい場所で用紙全体が写るように撮影し直すか、「項目を追加」から手入力してください。'),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('採血日時'),
              subtitle: Text(dateTimeFmt.format(set.takenAt), style: numberStyle(context, size: 18, weight: FontWeight.w600)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _pickDate,
            ),
          ),
          if (hasGas) ...[
            const SectionHeader('血液ガスの検体', icon: Icons.bloodtype_outlined),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<SpecimenType?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('自動推定')),
                  ButtonSegment(value: SpecimenType.arterial, label: Text('動脈血(A)')),
                  ButtonSegment(value: SpecimenType.venous, label: Text('静脈血(V)')),
                ],
                selected: {set.specimen.manual},
                onSelectionChanged: (s) => setState(() => set.specimen.manual = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                  set.specimen.sheetLabel != null
                      ? '用紙に「${set.specimen.sheetLabel!.label}」の記載があります'
                      : '用紙に検体種別の記載は見つかりませんでした（PO2・SO2・PCO2から推定します）',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          ],
          const SectionHeader('酸素投与', icon: Icons.air),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OxygenEditor(oxygen: set.oxygen, onChanged: () => setState(() {})),
          ),
          SectionHeader('検査値（${set.values.length}項目）',
              icon: Icons.list_alt, trailing: TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('項目を追加'))),
          for (final v in set.values)
            _ValueEditor(
              key: ObjectKey(v),
              value: v,
              catalog: catalog,
              onDelete: () => setState(() => set.values.remove(v)),
              onChanged: () => setState(() {}),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('項目を追加')),
          ),
        ],
      ),
      bottomNavigationBar: BottomActions(children: [
        FilledButton(onPressed: _finish, child: const Text('結果を見る')),
      ]),
    );
  }
}

class _ValueEditor extends StatefulWidget {
  const _ValueEditor({super.key, required this.value, required this.catalog, required this.onDelete, required this.onChanged});
  final LabValue value;
  final LabCatalog catalog;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late final TextEditingController _c;
  late final TextEditingController _lo;
  late final TextEditingController _hi;
  bool _showRange = false;

  LabValue get v => widget.value;

  @override
  void initState() {
    super.initState();
    final def = widget.catalog.byCode(v.code);
    _c = TextEditingController(text: v.value == null ? '' : formatNumber(v.value!, def?.decimals ?? 2));
    _lo = TextEditingController(text: v.sheetLow?.toString() ?? '');
    _hi = TextEditingController(text: v.sheetHigh?.toString() ?? '');
    _showRange = v.sheetLow != null || v.sheetHigh != null;
  }

  @override
  void dispose() {
    _c.dispose();
    _lo.dispose();
    _hi.dispose();
    super.dispose();
  }

  void _onValue(String s) {
    final x = double.tryParse(s.replaceAll(',', '.').trim());
    v.value = x;
    v.warnings.clear();
    v.uncertain = false;
    if (x != null) {
      final issue = widget.catalog.checkPlausibility(v.code, x);
      if (issue != null) {
        v.uncertain = true;
        v.warnings.add(issue.message);
      }
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.catalog.byCode(v.code);
    final lab = context.lab;
    final scheme = Theme.of(context).colorScheme;
    final flag = widget.catalog.flagFor(v);
    final color = flag.isHigh ? lab.high : (flag.isLow ? lab.low : null);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: v.uncertain ? lab.uncertainBg : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: v.uncertain ? lab.uncertainBorder : scheme.outlineVariant, width: v.uncertain ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (v.uncertain) Icon(Icons.warning_amber_rounded, color: lab.uncertainBorder, semanticLabel: '要確認'),
              if (v.uncertain) const SizedBox(width: 4),
              Expanded(
                flex: 4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(def?.name ?? v.code, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(def?.jpName ?? '', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ),
              Expanded(
                flex: 4,
                child: def != null && def.isQualitative
                    ? DropdownButtonFormField<double>(
                        initialValue: def.ordinals.any((o) => o.value == v.value) ? v.value : null,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true, hintText: '結果'),
                        style: numberStyle(context, size: 20, color: color),
                        items: [for (final o in def.ordinals) DropdownMenuItem(value: o.value, child: Text(o.label))],
                        onChanged: (x) => _onValue(x?.toString() ?? ''),
                      )
                    : TextField(
                  controller: _c,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  textAlign: TextAlign.right,
                  style: numberStyle(context, size: 22, color: color),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '値',
                    suffixIcon: flag.isAbnormal
                        ? Icon(flag.isHigh ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 20)
                        : null,
                  ),
                  onChanged: _onValue,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 64,
                child: Text(def?.unit ?? v.unit, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
              PopupMenuButton<String>(
                tooltip: 'その他',
                onSelected: (k) async {
                  if (k == 'del') widget.onDelete();
                  if (k == 'range') setState(() => _showRange = !_showRange);
                  if (k == 'item') {
                    final it = await showItemPicker(context);
                    if (it != null) {
                      setState(() {
                        v.code = it.code;
                        v.unit = it.unit;
                      });
                      _onValue(_c.text);
                    }
                  }
                  if (k == 'ok') {
                    setState(() {
                      v.uncertain = false;
                      v.warnings.clear();
                    });
                    widget.onChanged();
                  }
                },
                itemBuilder: (_) => [
                  if (v.uncertain) const PopupMenuItem(value: 'ok', child: Text('確認済みにする')),
                  const PopupMenuItem(value: 'item', child: Text('項目を変更')),
                  const PopupMenuItem(value: 'range', child: Text('用紙の基準値を入力/表示')),
                  const PopupMenuItem(value: 'del', child: Text('この項目を削除')),
                ],
              ),
            ],
          ),
          if (v.rawText != null)
            Text('読み取り: ${v.rawText}${v.sheetFlag != null ? '  (${v.sheetFlag})' : ''}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          for (final w in v.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text('・$w', style: TextStyle(fontSize: 12.5, color: v.uncertain ? scheme.onSurface : scheme.onSurfaceVariant)),
            ),
          if (v.uncertain)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    v.uncertain = false;
                    v.warnings.clear();
                  });
                  widget.onChanged();
                },
                icon: const Icon(Icons.check),
                label: const Text('原本と一致（確認済み）'),
              ),
            ),
          if (_showRange)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Row(children: [
                const Text('用紙の基準値'),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(hintText: '下限'),
                    onChanged: (s) {
                      v.sheetLow = double.tryParse(s);
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                ),
                const Text(' – '),
                Expanded(
                  child: TextField(
                    controller: _hi,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '上限'),
                    onChanged: (s) {
                      v.sheetHigh = double.tryParse(s);
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
