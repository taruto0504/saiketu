import 'dart:convert';

import 'package:flutter/material.dart';
import 'ai_screen.dart' show externalAis;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../data/lab_catalog_data.dart';
import '../models/lab_item.dart';
import '../services/app_services.dart';
import '../services/lab_catalog.dart';
import '../services/settings.dart';
import '../services/usage_stats.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final services = context.watch<AppServices>();
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('利用者', icon: Icons.badge_outlined),
          ListTile(
            title: const Text('職種・資格取得からの年数'),
            subtitle: Text('${labelOf(kRoles, s.role)}・${labelOf(kYearBands, s.yearsSinceLicense)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen(editing: true))),
          ),
          const SectionHeader('表示', icon: Icons.text_fields),
          ListTile(
            title: const Text('文字サイズ'),
            subtitle: Slider(
              value: s.textScale,
              min: 0.85,
              max: 1.6,
              divisions: 15,
              label: '${(s.textScale * 100).round()}%',
              onChanged: s.setTextScale,
            ),
            trailing: Text('${(s.textScale * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('背景'),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('白'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('黒'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, label: Text('端末に合わせる')),
                ],
                selected: {s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.setThemeMode(v.first),
              ),
            ]),
          ),
          SwitchListTile(
            title: const Text('結果を「異常値のみ表示」で開く'),
            value: s.abnormalOnly,
            onChanged: s.setAbnormalOnly,
          ),
          const SectionHeader('検査項目・判定', icon: Icons.tune),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('基準値の設定'),
            subtitle: const Text('施設の基準値に変更できます（用紙に記載があればそちらを優先）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RefRangeSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('追加項目'),
            subtitle: Text('ユーザー追加の検査項目（${context.watch<LabCatalog>().customItems.length}件）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomItemsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.rule),
            title: const Text('判定ルール'),
            subtitle: Text('v${services.rules.version}${services.usingCustomRules ? '（カスタム）' : '（組み込み）'}・'
                '${services.rules.diseases.length}疾患・検体チェック${services.rules.sampleChecks.length}件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())),
          ),
          const SectionHeader('セキュリティ', icon: Icons.lock_outline),
          SwitchListTile(
            title: const Text('パスコードロック'),
            subtitle: const Text('起動時・一定時間操作がないときにロック'),
            value: s.lockEnabled,
            onChanged: (v) async {
              if (v) {
                await showSetPasscodeDialog(context);
              } else {
                final ok = await confirmDialog(context, title: 'ロックを解除', message: 'パスコードロックを無効にしますか？', ok: '無効にする');
                if (ok) await s.clearPasscode();
              }
            },
          ),
          SwitchListTile(
            title: const Text('生体認証（Face ID・指紋）'),
            value: s.biometricEnabled,
            onChanged: !s.lockEnabled
                ? null
                : (v) async {
                    if (v) {
                      final auth = LocalAuthentication();
                      try {
                        final supported = await auth.isDeviceSupported();
                        final ok = supported &&
                            await auth.authenticate(localizedReason: '生体認証を有効にします', biometricOnly: true);
                        if (!ok) {
                          if (context.mounted) showSnack(context, '生体認証を有効にできませんでした');
                          return;
                        }
                      } catch (e) {
                        if (context.mounted) showSnack(context, '生体認証が利用できません');
                        return;
                      }
                    }
                    await s.setBiometric(v);
                  },
          ),
          ListTile(
            title: const Text('自動ロックまでの時間'),
            enabled: s.lockEnabled,
            trailing: DropdownButton<int>(
              value: s.autoLockMinutes,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1分')),
                DropdownMenuItem(value: 3, child: Text('3分')),
                DropdownMenuItem(value: 5, child: Text('5分')),
                DropdownMenuItem(value: 10, child: Text('10分')),
                DropdownMenuItem(value: 30, child: Text('30分')),
              ],
              onChanged: s.lockEnabled ? (v) => s.setAutoLockMinutes(v ?? 3) : null,
            ),
          ),
          const SectionHeader('データ', icon: Icons.storage),
          ListTile(
            title: const Text('自動削除'),
            subtitle: const Text('登録から指定日数を過ぎた採血データを自動で削除'),
            trailing: DropdownButton<int>(
              value: s.autoDeleteDays,
              items: const [
                DropdownMenuItem(value: 0, child: Text('しない')),
                DropdownMenuItem(value: 1, child: Text('1日後')),
                DropdownMenuItem(value: 7, child: Text('7日後')),
                DropdownMenuItem(value: 30, child: Text('30日後')),
                DropdownMenuItem(value: 90, child: Text('90日後')),
                DropdownMenuItem(value: 180, child: Text('180日後')),
                DropdownMenuItem(value: 365, child: Text('1年後')),
              ],
              onChanged: (v) async {
                await s.setAutoDeleteDays(v ?? 0);
                await services.runAutoDelete();
              },
            ),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('すべてのデータを削除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('フォルダ・採血データ・評価履歴・AIの会話（設定は残ります）'),
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'すべてのデータを削除', message: '保存されているすべてのフォルダとデータを削除します。元に戻せません。');
              if (!ok) return;
              await services.db.deleteAllRecords();
              services.dataChanged();
              if (context.mounted) showSnack(context, '削除しました');
            },
          ),
          const SectionHeader('AIアドバイス', icon: Icons.auto_awesome_outlined),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('いつも使うAI', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (k, l) in externalAis.map((a) => (a.id, a.name)).toList()..insert(0, ('app', 'このアプリ内（Claude）')))
                  ChoiceChip(label: Text(l), selected: s.preferredAi == k, onSelected: (_) => s.setPreferredAi(k)),
              ]),
              const SizedBox(height: 4),
              Text('ChatGPT・Gemini などを選ぶと、AIの画面でそのAIがいちばん上に出ます。送る内容（検査値と年齢・性別のみ）をコピーしてそのAIのアプリを開くので、貼り付けて送信します。各社の有料プランがそのまま使え、APIキーは不要です。',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('APIキー・モデル'),
            subtitle: Text('モデル: ${s.aiModel}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeyScreen())),
          ),
          const SectionHeader('利用統計（準備中）', icon: Icons.insights_outlined),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('今後、職種・資格取得からの年数ごとの利用状況を集計する予定です。今はこの端末内に回数を記録しているだけで、どこにも送信していません。',
                style: TextStyle(fontSize: 13)),
          ),
          SwitchListTile(
            title: const Text('統計の集計が始まったら協力する（匿名）'),
            value: s.statsConsent,
            onChanged: s.setStatsConsent,
          ),
          ListTile(
            title: const Text('記録している内容を見る'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showStats(context, s, services),
          ),
          const SectionHeader('このアプリについて', icon: Icons.info_outline),
          ListTile(
            title: const Text('免責事項'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('免責事項'),
                content: const Text(disclaimerText),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
              ),
            ),
          ),
          const ListTile(title: Text('LabSight'), subtitle: Text('バージョン 1.0.0')),
        ],
      ),
    );
  }
}

// ───────── APIキー ─────────

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final _key = TextEditingController();
  late final _model = TextEditingController(text: context.read<AppSettings>().aiModel);
  bool _hasKey = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    context.read<AppSettings>().apiKey().then((k) {
      if (mounted) setState(() => _hasKey = k != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('APIキー・モデル')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('AIアドバイスには Anthropic の Claude API を使用します。APIキーは端末のセキュア領域（Keychain/Keystore）に保存され、画面には表示されません。'),
          const SizedBox(height: 8),
          Text(_hasKey ? '現在: 設定済み' : '現在: 未設定', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _key,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _hasKey ? '新しいAPIキー（変更する場合）' : 'APIキー',
              hintText: 'sk-ant-...',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'モデル', helperText: '既定: ${AppSettings.defaultModel}'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (_key.text.trim().isNotEmpty) await s.setApiKey(_key.text);
              await s.setAiModel(_model.text);
              if (context.mounted) {
                showSnack(context, '保存しました');
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
          if (_hasKey) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await s.setApiKey(null);
                if (mounted) setState(() => _hasKey = false);
              },
              child: const Text('APIキーを削除'),
            ),
          ],
          const SizedBox(height: 24),
          const Text('送信されるのは検査値・計算値・前回値、年齢・性別、端末内の判定結果のみです。氏名・ID・フォルダ名・日付・自由記載は送信しません。',
              style: TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

void _showStats(BuildContext context, AppSettings s, AppServices services) {
  final months = s.stats.months;
  final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
  final payload = const JsonEncoder.withIndent(' ')
      .convert(s.stats.payload(role: s.role, years: s.yearsSinceLicense, rulesVersion: services.rules.version));
  Widget row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('記録している利用統計'),
      content: SizedBox(
        width: 480,
        child: ListView(shrinkWrap: true, children: [
          const Text('この端末内だけに保存しています（未送信）。検査値・患者情報・日時は含みません。', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          row('職種', labelOf(kRoles, s.role)),
          row('資格取得からの年数', labelOf(kYearBands, s.yearsSinceLicense)),
          if (keys.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('まだ記録はありません。')),
          for (final m in keys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${m.replaceFirst('-', '年')}月', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final e in months[m]!.entries) row(kStatEvents[e.key] ?? e.key, '${e.value}回'),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('送信する場合のデータ形式（開発者向け）', style: TextStyle(fontSize: 13)),
            children: [SelectableText(payload, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))],
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await s.stats.clearCounts();
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) showSnack(context, '利用統計の記録を消去しました');
          },
          child: const Text('記録を消去'),
        ),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('閉じる')),
      ],
    ),
  );
}

// ───────── 基準値 ─────────

class RefRangeSettingsScreen extends StatelessWidget {
  const RefRangeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    return Scaffold(
      appBar: AppBar(title: const Text('基準値の設定')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('優先順位: 用紙に記載の基準値 ＞ ここで設定した基準値 ＞ 既定値（性別・動脈血/静脈血を考慮）\n\n'
                '既定値は、JCCLS（日本臨床検査標準協議会）の共用基準範囲がある${jcclsSharedRangeCodes.length}項目はその値を使っています。'
                '共用基準範囲は健常者のデータから作られた全国共通の基準範囲で、日本臨床検査医学会もその使用を勧めています。'
                'それ以外の項目は一般的な目安です。施設の基準値が異なる場合はここで変更してください。'),
          ),
          for (final cat in LabCategory.values)
            if (catalog.byCategory(cat).isNotEmpty) ...[
              SectionHeader(cat.label),
              for (final def in catalog.byCategory(cat))
                Builder(builder: (context) {
                  final user = catalog.userRanges[def.code];
                  final d = catalog.defaultRange(def);
                  return ListTile(
                    title: Text(def.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${user != null ? '設定: ${user.format(def.decimals)}（既定 ${d.format(def.decimals)}）' : '既定: ${d.format(def.decimals)}'} ${def.unit}'
                      '${def.lowM != null ? '\n男性 ${RefRange(def.lowM, def.highM).format(def.decimals)} / 女性 ${RefRange(def.lowF, def.highF).format(def.decimals)}' : ''}'
                      '${def.isGas ? '\n静脈血 ${RefRange(def.venousLow, def.venousHigh).format(def.decimals)}' : ''}'
                      '${def.rangeNote != null ? '\n${def.rangeNote}' : ''}'
                      '${def.isCustom ? '' : '\n出典: ${defaultRangeSource(def.code)}'}',
                    ),
                    trailing: Icon(user != null ? Icons.edit : Icons.edit_outlined,
                        color: user != null ? Theme.of(context).colorScheme.primary : null),
                    onTap: () => _edit(context, def),
                  );
                }),
            ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, LabItemDef def) async {
    final catalog = context.read<LabCatalog>();
    final services = context.read<AppServices>();
    final cur = catalog.userRanges[def.code] ?? catalog.defaultRange(def);
    final lo = TextEditingController(text: cur.low?.toString() ?? '');
    final hi = TextEditingController(text: cur.high?.toString() ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${def.name} の基準値（${def.unit}）'),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: lo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: '下限'),
            ),
          ),
          const Text('  –  '),
          Expanded(
            child: TextField(
              controller: hi,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: '上限'),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('既定に戻す')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('保存')),
        ],
      ),
    );
    if (r == 'reset') {
      catalog.setUserRange(def.code, null);
    } else if (r == 'save') {
      final l = double.tryParse(lo.text.trim()), h = double.tryParse(hi.text.trim());
      if (l != null && h != null && l > h) {
        if (context.mounted) showSnack(context, '下限が上限より大きくなっています');
        return;
      }
      catalog.setUserRange(def.code, RefRange(l, h));
    } else {
      return;
    }
    await services.saveCatalogSettings();
  }
}

// ───────── 追加項目 ─────────

class CustomItemsScreen extends StatelessWidget {
  const CustomItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final items = catalog.customItems;
    return Scaffold(
      appBar: AppBar(title: const Text('追加項目')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('項目を追加'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('組み込み項目にない検査を追加できます。\n別名を登録すると写真からの読み取りでも認識されます。', textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final it in items)
                  Card(
                    child: ListTile(
                      title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${it.jpName}  基準 ${RefRange(it.low, it.high).format(it.decimals)} ${it.unit}'
                          '${it.aliases.isNotEmpty ? '\n別名: ${it.aliases.join(', ')}' : ''}'),
                      onTap: () => _edit(context, it),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(context, title: '項目を削除', message: '「${it.name}」を削除しますか？（保存済みデータの値は残ります）');
                          if (!ok || !context.mounted) return;
                          context.read<LabCatalog>().removeCustom(it.code);
                          await context.read<AppServices>().saveCatalogSettings();
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, LabItemDef? it) async {
    final name = TextEditingController(text: it?.name ?? '');
    final jp = TextEditingController(text: it?.jpName ?? '');
    final unit = TextEditingController(text: it?.unit ?? '');
    final lo = TextEditingController(text: it?.low?.toString() ?? '');
    final hi = TextEditingController(text: it?.high?.toString() ?? '');
    final clo = TextEditingController(text: it?.critLow?.toString() ?? '');
    final chi = TextEditingController(text: it?.critHigh?.toString() ?? '');
    final aliases = TextEditingController(text: it?.aliases.join(', ') ?? '');
    final dec = TextEditingController(text: (it?.decimals ?? 1).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it == null ? '項目を追加' : '項目を編集'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '表示名（例: KL-6）*')),
            const SizedBox(height: 8),
            TextField(controller: jp, decoration: const InputDecoration(labelText: '日本語名')),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: const InputDecoration(labelText: '単位')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: lo, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: '基準下限'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: hi, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: '基準上限'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: clo, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: '危険値（低）'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: chi, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: '危険値（高）'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: aliases, decoration: const InputDecoration(labelText: '別名（カンマ区切り）', hintText: '例: KL6, シアル化糖鎖抗原KL-6')),
            const SizedBox(height: 8),
            TextField(controller: dec, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '小数点以下の桁数')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final n = name.text.trim();
    if (n.isEmpty) {
      showSnack(context, '表示名を入力してください');
      return;
    }
    final catalog = context.read<LabCatalog>();
    final code = it?.code ?? 'X_${normalizeName(n)}_${DateTime.now().millisecondsSinceEpoch % 100000}';
    final existing = catalog.codeForAlias(n);
    if (it == null && existing != null && catalog.byCode(existing)?.isCustom != true) {
      showSnack(context, '「$n」は組み込み項目（${catalog.byCode(existing)!.name}）として登録済みです');
      return;
    }
    double? p(TextEditingController c) => double.tryParse(c.text.trim());
    catalog.addOrUpdateCustom(LabItemDef(
      code: code,
      name: n,
      jpName: jp.text.trim(),
      category: LabCategory.custom,
      unit: unit.text.trim(),
      low: p(lo),
      high: p(hi),
      critLow: p(clo),
      critHigh: p(chi),
      aliases: aliases.text.split(RegExp(r'[,、，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      decimals: int.tryParse(dec.text.trim())?.clamp(0, 4) ?? 1,
      isCustom: true,
    ));
    await context.read<AppServices>().saveCatalogSettings();
  }
}

// ───────── 判定ルール ─────────

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppServices>();
    final r = services.rules;
    return Scaffold(
      appBar: AppBar(title: const Text('判定ルール')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '疾患推定は端末内のルール（JSON）で行います。ルールファイルを差し替えることで、アプリを更新せずに判定内容を更新できます。\n'
              '現在: v${r.version}${services.usingCustomRules ? '（カスタム）' : '（組み込み）'}',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _import(context),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('ルールJSONを読み込む'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final bundle = DefaultAssetBundle.of(context);
                  await Clipboard.setData(ClipboardData(
                      text: await services.db.getKv('rules_json') ?? await bundle.loadString(AppServices.rulesAsset)));
                  if (context.mounted) showSnack(context, '現在のルールJSONをコピーしました');
                },
                icon: const Icon(Icons.copy),
                label: const Text('コピー'),
              ),
              if (services.usingCustomRules)
                OutlinedButton.icon(
                  onPressed: () async {
                    await services.setCustomRules(null);
                    if (context.mounted) showSnack(context, '組み込みルールに戻しました');
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('組み込みに戻す'),
                ),
            ]),
          ),
          SectionHeader('疾患・病態（${r.diseases.length}）'),
          for (final d in r.diseases)
            ListTile(dense: true, title: Text(d.name), subtitle: Text('${d.category}・所見${d.findings.length}・否定的所見${d.against.length}')),
          SectionHeader('検体エラーチェック（${r.sampleChecks.length}）'),
          for (final s in r.sampleChecks) ListTile(dense: true, title: Text(s.name)),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final c = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    if (clip?.text != null && clip!.text!.trimLeft().startsWith('{')) c.text = clip.text!;
    if (!context.mounted) return;
    final json = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ルールJSONを読み込む'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(hintText: '{"version": "...", "diseases": [...], "sampleChecks": [...]}'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('読み込む')),
        ],
      ),
    );
    if (json == null || json.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<AppServices>().setCustomRules(json);
      if (context.mounted) showSnack(context, 'ルールを更新しました');
    } catch (e) {
      if (context.mounted) showSnack(context, 'ルールの形式が正しくありません: $e');
    }
  }
}
