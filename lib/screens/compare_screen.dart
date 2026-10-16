import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/clinical_calc.dart';
import '../services/lab_catalog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ai_screen.dart';
import 'diagnosis_screen.dart';

const trendKeyItems = [
  'WBC', 'HB', 'PLT', 'CRP', 'PCT', 'CRE', 'BUN', 'EGFR', 'NA', 'K', 'AST', 'ALT', 'TBIL', 'LDH', 'CK',
  'GLU', 'ALB', 'PT_INR', 'DDIMER', 'FDP', 'BNP', 'NTPROBNP', 'TNT', 'TNI', 'PH', 'PCO2', 'PO2', 'HCO3', 'LAC', 'NH3',
];

enum Trend { improved, worsened, unchanged, neutral }

/// 基準範囲からの「はずれ具合」で改善/悪化を判定する。
Trend trendOf(double prev, double cur, RefRange r) {
  if (r.isEmpty) return Trend.neutral;
  final width = (r.low != null && r.high != null && r.high! > r.low!) ? r.high! - r.low! : (r.high ?? r.low ?? 1).abs();
  double dist(double x) {
    if (r.high != null && x > r.high!) return (x - r.high!) / (width == 0 ? 1 : width);
    if (r.low != null && x < r.low!) return (r.low! - x) / (width == 0 ? 1 : width);
    return 0;
  }

  final a = dist(prev), b = dist(cur);
  if (a == 0 && b == 0) return Trend.unchanged;
  if ((a - b).abs() < 0.02) return Trend.unchanged;
  return b < a ? Trend.improved : Trend.worsened;
}

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.folderId, this.currentId});
  final String folderId;
  final String? currentId;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<LabSet> _sets = [];
  LabSet? _prev;
  LabSet? _cur;
  String? _trendItem;
  bool _changedOnly = false;

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().settings.stats.track('compare');
    _load();
  }

  Future<void> _load() async {
    final sets = await context.read<AppServices>().db.labSets(widget.folderId);
    if (!mounted || sets.length < 2) {
      setState(() => _sets = sets);
      return;
    }
    var ci = sets.length - 1;
    if (widget.currentId != null) {
      final i = sets.indexWhere((s) => s.id == widget.currentId);
      if (i > 0) ci = i;
    }
    setState(() {
      _sets = sets;
      _cur = sets[ci];
      _prev = sets[ci - 1];
      final codes = _codesWithTrend();
      _trendItem = codes.isNotEmpty ? codes.first : null;
    });
  }

  List<String> _codesWithTrend() {
    final counts = <String, int>{};
    for (final s in _sets) {
      for (final v in s.values) {
        if (v.value != null) counts[v.code] = (counts[v.code] ?? 0) + 1;
      }
    }
    final key = trendKeyItems.where((c) => (counts[c] ?? 0) >= 2).toList();
    final others = counts.entries.where((e) => e.value >= 2 && !trendKeyItems.contains(e.key)).map((e) => e.key);
    return [...key, ...others];
  }

  Widget _setPicker(String label, LabSet? value, ValueChanged<LabSet?> onChanged) => Expanded(
        child: DropdownButtonFormField<LabSet>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final s in _sets) DropdownMenuItem(value: s, child: Text(dateTimeFmt.format(s.takenAt)))],
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    if (_sets.length < 2 || _prev == null || _cur == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('比較・推移')),
        body: Center(child: _sets.isEmpty ? const CircularProgressIndicator() : const Text('比較には2件以上のデータが必要です')),
      );
    }
    // 古い方を「前回」として扱う
    var a = _prev!, b = _cur!;
    if (a.takenAt.isAfter(b.takenAt)) (a, b) = (b, a);
    final sex = b.context.sex ?? a.context.sex;
    final spec = effectiveSpecimen(b);
    final pa = a.valueMap, pb = b.valueMap;
    final codes = <String>[
      for (final def in catalog.all)
        if (pa.containsKey(def.code) || pb.containsKey(def.code)) def.code,
    ];
    final lab = context.lab;
    final scheme = Theme.of(context).colorScheme;
    final days = b.takenAt.difference(a.takenAt).inHours / 24;

    final rows = <Widget>[];
    var improved = 0, worsened = 0;
    for (final code in codes) {
      final def = catalog.byCode(code)!;
      final x = pa[code], y = pb[code];
      Trend t = Trend.neutral;
      if (x != null && y != null) {
        final lv = b.valueOf(code) ?? LabValue(code: code, value: y);
        t = trendOf(x, y, catalog.rangeFor(lv, sex: sex, specimen: spec));
        if (t == Trend.improved) improved++;
        if (t == Trend.worsened) worsened++;
      }
      if (_changedOnly && t != Trend.improved && t != Trend.worsened) continue;
      final flag = y == null ? LabFlag.unknown : catalog.flagFor(b.valueOf(code)!, sex: sex, specimen: spec);
      final color = switch (t) {
        Trend.improved => lab.improved,
        Trend.worsened => lab.worsened,
        _ => scheme.onSurfaceVariant,
      };
      final d = (x != null && y != null) ? y - x : null;
      rows.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
        child: Row(children: [
          Expanded(flex: 4, child: Text(def.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Expanded(
            flex: 4,
            child: Text(x == null ? '—' : formatNumber(x, def.decimals),
                textAlign: TextAlign.right, style: numberStyle(context, size: 16, weight: FontWeight.w500)),
          ),
          Expanded(
            flex: 4,
            child: Text(y == null ? '—' : formatNumber(y, def.decimals),
                textAlign: TextAlign.right,
                style: numberStyle(context,
                    size: 18, color: flag.isHigh ? lab.high : flag.isLow ? lab.low : null)),
          ),
          Expanded(
            flex: 5,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(
                child: Text(
                  d == null ? '' : '${d >= 0 ? '+' : '−'}${formatNumber(d.abs(), def.decimals)}',
                  textAlign: TextAlign.right,
                  style: numberStyle(context, size: 15, weight: FontWeight.w600, color: color),
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 22,
                child: switch (t) {
                  Trend.improved => Icon(Icons.trending_up, size: 18, color: color, semanticLabel: '改善'),
                  Trend.worsened => Icon(Icons.trending_down, size: 18, color: color, semanticLabel: '悪化'),
                  _ => null,
                },
              ),
            ]),
          ),
        ]),
      ));
    }

    final trendCodes = _codesWithTrend();
    return Scaffold(
      appBar: AppBar(title: const Text('比較・推移')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              _setPicker('前回', _prev, (s) => setState(() => _prev = s)),
              const SizedBox(width: 8),
              _setPicker('今回', _cur, (s) => setState(() => _cur = s)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('間隔 約${days.toStringAsFixed(1)}日 ・ 改善 $improved項目 ・ 悪化 $worsened項目'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 12, children: [
              _legend(Icons.trending_up, '改善（基準範囲に近づいた）', lab.improved),
              _legend(Icons.trending_down, '悪化（基準範囲から離れた）', lab.worsened),
            ]),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('変化のあった項目のみ'),
            value: _changedOnly,
            onChanged: (v) => setState(() => _changedOnly = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              child: const Row(children: [
                Expanded(flex: 4, child: Text('項目')),
                Expanded(flex: 4, child: Text('前回', textAlign: TextAlign.right)),
                Expanded(flex: 4, child: Text('今回', textAlign: TextAlign.right)),
                Expanded(flex: 5, child: Text('変化量', textAlign: TextAlign.right)),
              ]),
            ),
          ),
          ...rows,
          SectionHeader('推移グラフ（${_sets.length}回分）', icon: Icons.show_chart),
          if (trendCodes.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('2回以上測定された項目がありません'))
          else ...[
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in trendCodes)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(catalog.byCode(c)?.name ?? c),
                        selected: _trendItem == c,
                        onSelected: (_) => setState(() => _trendItem = c),
                      ),
                    ),
                ],
              ),
            ),
            if (_trendItem != null) _TrendChart(code: _trendItem!, sets: _sets, sex: sex),
          ],
          const DisclaimerFooter(),
        ],
      ),
      bottomNavigationBar: BottomActions(children: [
        FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DiagnosisScreen(set: b, previous: a, reevaluateOnOpen: true))),
          icon: const Icon(Icons.manage_search),
          label: const Text('疾患推定で再評価'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AiScreen(set: b, previous: a))),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('AIで再評価'),
        ),
      ]),
    );
  }

  Widget _legend(IconData i, String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16, color: c),
        const SizedBox(width: 2),
        Text(t, style: TextStyle(fontSize: 12, color: c)),
      ]);
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.code, required this.sets, required this.sex});
  final String code;
  final List<LabSet> sets;
  final String? sex;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final def = catalog.byCode(code);
    final scheme = Theme.of(context).colorScheme;
    final lab = context.lab;
    final pts = <({DateTime t, double v, LabFlag f})>[];
    RefRange? range;
    for (final s in sets) {
      final lv = s.valueOf(code);
      if (lv == null) continue;
      final spec = effectiveSpecimen(s);
      range ??= catalog.rangeFor(lv, sex: sex, specimen: spec);
      pts.add((t: s.takenAt, v: lv.value!, f: catalog.flagFor(lv, sex: sex, specimen: spec)));
    }
    if (pts.length < 2) return const SizedBox.shrink();
    final values = [for (final p in pts) p.v, if (range?.low != null) range!.low!, if (range?.high != null) range!.high!];
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.15 + (maxY.abs() * 0.02) + 0.01;
    minY -= pad;
    maxY += pad;
    final fmt = DateFormat('M/d\nHH:mm');
    final dec = def?.decimals ?? 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text('${def?.name ?? code}（${def?.unit ?? ''}）  基準 ${range?.format(dec) ?? '—'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (pts.length - 1).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
                if (range != null && (range.low != null || range.high != null))
                  HorizontalRangeAnnotation(
                    y1: range.low ?? minY,
                    y2: range.high ?? maxY,
                    color: scheme.primary.withValues(alpha: 0.08),
                  ),
              ]),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (v, meta) => (v == meta.min || v == meta.max)
                        ? const SizedBox.shrink()
                        : SideTitleWidget(
                            meta: meta,
                            child: Text(formatNumber(v, dec), style: const TextStyle(fontSize: 10.5)),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= pts.length || (v - i).abs() > 0.01) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(fmt.format(pts[i].t), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].v)],
                  color: scheme.primary,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    getDotPainter: (spot, _, _, i) {
                      final f = pts[i].f;
                      final c = f.isHigh ? lab.high : f.isLow ? lab.low : scheme.primary;
                      return FlDotCirclePainter(radius: f.isCritical ? 6 : 4.5, color: c, strokeWidth: 2, strokeColor: scheme.surface);
                    },
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${fmt.format(pts[s.x.round()].t).replaceAll('\n', ' ')}\n${formatNumber(s.y, dec)}',
                        TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
