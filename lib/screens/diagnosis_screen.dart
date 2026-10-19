import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/rule_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/finish.dart';
import 'ai_screen.dart';
import 'context_input_screen.dart';

/// 疾患推定の状態（評価履歴・再評価）。
class DiagnosisController extends ChangeNotifier {
  DiagnosisController(this.services, this.set, this.previous, {this.reevaluateOnOpen = false});

  final AppServices services;
  final LabSet set;
  final LabSet? previous;

  /// 開いた時点で再評価する（比較画面から、選んだ前回値で再評価する場合など）。
  final bool reevaluateOnOpen;
  final List<EvaluationResult> history = [];
  bool loading = true;

  EvaluationResult? get current => history.isEmpty ? null : history.last;
  EvaluationResult? get before => history.length < 2 ? null : history[history.length - 2];

  Future<void> init() async {
    services.settings.stats.track('diag_view');
    if (set.isSaved) {
      history.addAll(await services.db.evaluations(set.id));
    }
    if (history.isEmpty) {
      await evaluate(useContext: false);
    } else if (reevaluateOnOpen) {
      await evaluate(useContext: !set.context.isEmpty);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> evaluate({required bool useContext}) async {
    final r = services.engine.evaluate(set, previous: previous, useContext: useContext);
    history.add(r);
    if (set.isSaved) {
      await services.db.saveLabSet(set);
      await services.db.saveEvaluation(set.id, r);
    }
    notifyListeners();
  }

  Future<void> addContextAndReevaluate(BuildContext context) async {
    final updated = await Navigator.push<PatientContext>(
      context,
      MaterialPageRoute(builder: (_) => ContextInputScreen(initial: set.context, set: set)),
    );
    if (updated == null) return;
    set.context = updated;
    await evaluate(useContext: true);
  }
}

class DiagnosisScreen extends StatelessWidget {
  const DiagnosisScreen({super.key, required this.set, this.previous, this.reevaluateOnOpen = false});
  final LabSet set;
  final LabSet? previous;
  final bool reevaluateOnOpen;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => DiagnosisController(ctx.read<AppServices>(), set, previous, reevaluateOnOpen: reevaluateOnOpen)..init(),
      child: Builder(builder: (context) {
        final c = context.watch<DiagnosisController>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('疾患推定'),
            actions: [
              IconButton(
                tooltip: '評価履歴',
                icon: const Icon(Icons.history),
                onPressed: () => _showHistory(context, c),
              ),
            ],
          ),
          body: const DiagnosisPanel(),
          bottomNavigationBar: BottomActions(children: [
            OutlinedButton(onPressed: () => finishFlow(context, set), child: const Text('終了')),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => AiScreen(set: set, previous: previous))),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('AI'),
            ),
            FilledButton.icon(
              onPressed: () => c.addContextAndReevaluate(context),
              icon: const Icon(Icons.playlist_add),
              label: const Text('情報を追加して再評価'),
            ),
          ]),
        );
      }),
    );
  }
}

void _showHistory(BuildContext context, DiagnosisController c) {
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        children: [
          const SectionHeader('評価履歴', icon: Icons.history),
          if (c.history.isEmpty) const ListTile(title: Text('履歴はありません')),
          for (final (i, e) in c.history.indexed.toList().reversed)
            ExpansionTile(
              title: Text('${i + 1}回目  ${dateTimeFmt.format(e.at)}'),
              subtitle: Text('${e.stage == 1 ? '採血データのみ' : '追加情報あり'}・${e.diseases.length}件'
                  '${e.contextUsed.isEmpty ? '' : '\n${e.contextUsed.entries.map((x) => '${x.key}: ${x.value}').join(' / ')}'}'),
              children: [
                for (final (j, d) in e.diseases.take(10).indexed)
                  ListTile(dense: true, title: Text('${j + 1}. ${d.name}'), trailing: Text('可能性 ${d.likelihood}')),
              ],
            ),
        ],
      ),
    ),
  );
}

/// 疾患推定の表示部（タブレットの右ペインでも使用）。
class DiagnosisPanel extends StatelessWidget {
  const DiagnosisPanel({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DiagnosisController>();
    final e = c.current;
    if (c.loading || e == null) return const Center(child: CircularProgressIndicator());
    final diff = diffEvaluations(c.before, e);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(e.stage == 1 ? Icons.science_outlined : Icons.person_search_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.stage == 1 ? '第1段階：採血データのみの評価' : '第2段階：追加情報を含めた評価',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 16),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '端末内のルールベース判定（ルール v${e.rulesVersion}）。可能性の高い順に表示しています。'
              '${e.comparedWithPrevious ? '前回値からの変化も評価に使用しています。' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
            if (e.contextUsed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final x in e.contextUsed.entries)
                  Chip(visualDensity: VisualDensity.compact, label: Text('${x.key}: ${x.value}', style: const TextStyle(fontSize: 12))),
              ]),
            ],
          ]),
        ),
        if (e.sampleWarnings.isNotEmpty)
          for (final w in e.sampleWarnings) SampleWarningCard(w),
        if (c.before != null && diff.items.any((d) => d.change != RankChange.same || d.added.isNotEmpty) ||
            diff.dropped.isNotEmpty)
          _ChangeSummary(diff: diff),
        if (e.diseases.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('ルールに該当する疾患・病態はありませんでした。\n（判定ルールでカバーしていない病態もあります。臨床所見と併せて判断してください）'),
          ),
        // 可能性の高さごとに見出しを付ける
        for (final (i, d) in diff.items.indexed) ...[
          if (i == 0 || diff.items[i - 1].result.likelihood != d.result.likelihood)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                switch (d.result.likelihood) { '高' => '可能性が高い', '中' => '可能性：中くらい', _ => '可能性は低いが考えておきたい' },
                style: TextStyle(fontWeight: FontWeight.w700, color: _likeColor(context, d.result.likelihood)),
              ),
            ),
          _DiseaseCard(d: d, showChange: c.before != null),
        ],
        if (diff.dropped.isNotEmpty) ...[
          const SectionHeader('今回の評価で候補から外れた疾患', icon: Icons.remove_circle_outline),
          for (final d in diff.dropped)
            ListTile(dense: true, leading: const Icon(Icons.arrow_downward), title: Text(d.name)),
        ],
        const DisclaimerFooter(),
      ],
    );
  }
}

class SampleWarningCard extends StatelessWidget {
  const SampleWarningCard(this.w, {super.key});
  final SampleWarning w;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: lab.uncertainBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lab.uncertainBorder, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.report_problem_outlined, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text('検体エラーの可能性：${w.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text(w.message, style: const TextStyle(fontSize: 13)),
        if (w.evidence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('根拠: ${w.evidence.join('、')}', style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

class _ChangeSummary extends StatelessWidget {
  const _ChangeSummary({required this.diff});
  final EvaluationDiff diff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = diff.items.where((d) => d.change == RankChange.up).toList();
    final down = diff.items.where((d) => d.change == RankChange.down).toList();
    final added = diff.items.where((d) => d.change == RankChange.newEntry).toList();
    final drivers = <String>{
      for (final d in diff.items)
        for (final e in d.added)
          if (e.fromContext) e.text,
    };
    Widget line(IconData icon, String label, List<String> names) => names.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('$label：${names.join('、')}')),
            ]),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('前回の評価からの変化', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          line(Icons.fiber_new_outlined, '新規', added.map((d) => d.result.name).toList()),
          line(Icons.arrow_upward, '順位が上昇', up.map((d) => '${d.result.name}（${d.prevRank}→${d.rank}位）').toList()),
          line(Icons.arrow_downward, '順位が低下', down.map((d) => '${d.result.name}（${d.prevRank}→${d.rank}位）').toList()),
          line(Icons.remove_circle_outline, '候補外', diff.dropped.map((d) => d.name).toList()),
          if (drivers.isNotEmpty) ...[
            const Divider(height: 16),
            const Text('評価を変えた追加情報', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final t in drivers) Text('・$t'),
          ],
        ]),
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard({required this.d, required this.showChange});
  final DiseaseDiff d;
  final bool showChange;

  @override
  Widget build(BuildContext context) {
    final r = d.result;
    final scheme = Theme.of(context).colorScheme;
    final lab = context.lab;
    final likeColor = _likeColor(context, r.likelihood);
    final level = switch (r.likelihood) { '高' => 3, '中' => 2, _ => 1 };
    Widget? badge;
    if (showChange) {
      badge = switch (d.change) {
        RankChange.up => _Badge(Icons.arrow_upward, '上昇（${d.prevRank}→${d.rank}位）', scheme.primary),
        RankChange.down => _Badge(Icons.arrow_downward, '低下（${d.prevRank}→${d.rank}位）', scheme.outline),
        RankChange.newEntry => _Badge(Icons.fiber_new_outlined, '新規', scheme.primary),
        RankChange.same => null,
      };
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: level > 1 ? likeColor : scheme.outlineVariant, width: level > 1 ? 1.5 : 1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: d.rank <= 3,
          tilePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: likeColor.withValues(alpha: 0.15),
            child: Text('${d.rank}', style: TextStyle(fontWeight: FontWeight.w800, color: likeColor)),
          ),
          title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                // 可能性（3段階のメーター付き）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: level > 1 ? likeColor.withValues(alpha: 0.12) : null,
                    border: Border.all(color: likeColor, width: 1.5),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('可能性 ${r.likelihood}', style: TextStyle(color: likeColor, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(width: 6),
                    for (var i = 1; i <= 3; i++)
                      Container(
                        width: 6,
                        height: 11,
                        margin: const EdgeInsets.only(left: 2),
                        decoration: BoxDecoration(
                          color: likeColor.withValues(alpha: i <= level ? 1 : 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(6)),
                  child: Text(r.category, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ),
                ?badge,
              ]),
              // 根拠になった値（短い札で）
              if (keyValues(r.support).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final k in keyValues(r.support))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: k.arrow == '↑' ? lab.high : k.arrow == '↓' ? lab.low : scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(k.label,
                            style: TextStyle(
                                fontSize: 13,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: k.arrow == '↑' ? lab.high : k.arrow == '↓' ? lab.low : null)),
                      ),
                  ]),
                ),
            ]),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.alert != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: lab.critBg, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.priority_high, color: lab.critFg, size: 18),
                  const SizedBox(width: 4),
                  Expanded(child: Text(r.alert!, style: TextStyle(color: lab.critFg, fontWeight: FontWeight.w700))),
                ]),
              ),
            const Text('なぜ疑うか', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in r.support) _EvidenceLine(e: e, positive: true, isNew: d.added.contains(e)),
            if (r.against.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('否定的な所見', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final e in r.against) _EvidenceLine(e: e, positive: false, isNew: d.added.contains(e)),
            ],
            if (d.removed.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('前回評価から外れた根拠', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final e in d.removed)
                Text('・${e.text}', style: TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)),
            ],
            if (r.tests.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('追加で確認したい検査', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final t in r.tests)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.add_task, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t)),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({required this.e, required this.positive, required this.isNew});
  final Evidence e;
  final bool positive;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(positive ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 17, color: positive ? scheme.primary : scheme.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: e.text, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            if (e.note != null) TextSpan(text: '\n${e.note}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            if (e.fromContext) TextSpan(text: '  [追加情報]', style: TextStyle(fontSize: 11.5, color: scheme.primary)),
            if (isNew) TextSpan(text: '  [今回追加]', style: TextStyle(fontSize: 11.5, color: scheme.primary, fontWeight: FontWeight.w700)),
          ])),
        ),
      ]),
    );
  }
}

Color _likeColor(BuildContext context, String likelihood) {
  final scheme = Theme.of(context).colorScheme;
  return switch (likelihood) { '高' => context.lab.high, '中' => scheme.primary, _ => scheme.outline };
}

/// 根拠の文（「Hb 6.2 g/dL（基準 11.6–14.8）↓、BUN …」）から、カードの見出しに出す短い値の札を作る（最大4つ）。
List<({String label, String? arrow})> keyValues(List<Evidence> support) {
  final out = <({String label, String? arrow})>[];
  final seen = <String>{};
  final re = RegExp(r'^(.+?)\s+([<>]?[-\d.]+)(?:\s*[^（↑↓]*)?(?:（[^）]*）)?\s*([↑↓])?$');
  for (final part in support.expand((e) => e.text.split('、'))) {
    final t = part.trim();
    final m = re.firstMatch(t);
    final key = m?.group(1) ?? t;
    final label = m != null ? '${m.group(1)} ${m.group(2)}${m.group(3) ?? ''}' : t.replaceFirst(RegExp(r'\s*（基準[^）]*）'), '');
    if (label.isEmpty || label.length > 24 || !seen.add(key)) continue;
    out.add((label: label, arrow: m?.group(3)));
    if (out.length >= 4) break;
  }
  return out;
}
