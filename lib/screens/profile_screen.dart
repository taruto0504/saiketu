import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../services/usage_stats.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 職種と資格取得からの年数の選択。初回は同意画面の次に表示し、設定から変更もできる。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.editing = false});

  /// 設定画面から開いたとき true。
  final bool editing;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String? _role = context.read<AppSettings>().role;
  late String? _years = context.read<AppSettings>().yearsSinceLicense;

  Future<void> _save() async {
    final s = context.read<AppSettings>();
    await s.setProfile(role: _role!, years: _years!);
    s.stats.installId; // 統計用IDを用意しておく
    if (!mounted) return;
    if (widget.editing) {
      showSnack(context, '保存しました');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('職種・資格取得からの年数')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, widget.editing ? 16 : 32, 20, 16),
              children: [
                if (!widget.editing) ...[
                  Row(children: [
                    Icon(Icons.biotech_outlined, size: 40, color: scheme.primary),
                    const SizedBox(width: 12),
                    Text('LabSight', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
                  ]),
                  const SizedBox(height: 4),
                  Text('はじめに教えてください', style: t.titleMedium),
                  const SizedBox(height: 20),
                ],
                const Text('あなたの職種と、資格を取得してからの年数を選んでください。あとから設定で変更できます。'),
                const SectionHeader('職種'),
                _choices(kRoles, _role, (v) => setState(() => _role = v)),
                const SectionHeader('資格取得からの年数'),
                Text('勤務年数ではなく、現在の資格（免許）を取得してからの年数を選んでください。',
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                _choices(kYearBands, _years, (v) => setState(() => _years = v)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: context.lab.subtle, borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    'この情報はこの端末内にだけ保存します。今後、アプリの改善のために職種・年数ごとの利用状況を統計として集計することを予定しています。'
                    '集計を始める前に改めて同意を確認し、同意がなければ送信しません。氏名や患者の情報は統計に含めません。',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomActions(children: [
        FilledButton(
          onPressed: _role != null && _years != null ? _save : null,
          child: Text(widget.editing ? '保存' : '次へ'),
        ),
      ]),
    );
  }

  Widget _choices(List<(String, String)> items, String? selected, ValueChanged<String> onTap) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 3 : 2;
      final w = (c.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (key, label) in items)
          SizedBox(
            width: w,
            height: 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: selected == key ? scheme.primaryContainer : null,
                foregroundColor: selected == key ? scheme.onPrimaryContainer : scheme.onSurface,
                side: BorderSide(color: selected == key ? scheme.primary : scheme.outlineVariant, width: selected == key ? 2 : 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => onTap(key),
              child: Semantics(selected: selected == key, child: Text(label, textAlign: TextAlign.center)),
            ),
          ),
      ]);
    });
  }
}
