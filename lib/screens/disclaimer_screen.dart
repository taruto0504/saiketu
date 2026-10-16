import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../theme.dart';

/// 初回起動時の免責同意画面。
class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({super.key});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                children: [
                  Row(children: [
                    Icon(Icons.biotech_outlined, size: 40, color: scheme.primary),
                    const SizedBox(width: 12),
                    Text('LabSight', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
                  ]),
                  const SizedBox(height: 4),
                  Text('採血データ解析・診療サポート（医療従事者向け）', style: t.titleSmall),
                  const SizedBox(height: 28),
                  Text('ご利用の前に', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.lab.subtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(disclaimerText, style: t.bodyLarge?.copyWith(height: 1.7)),
                  ),
                  const SizedBox(height: 20),
                  _point(context, Icons.wifi_off, 'オフラインで動作します。読み取り・判定はすべて端末内で行います（AIアドバイスのみ通信を使用）。'),
                  _point(context, Icons.lock_outline, 'データは端末内に暗号化して保存します。氏名・生年月日などは保存しません。'),
                  _point(context, Icons.fact_check_outlined, '読み取った値は必ず確認画面で原本と照合してください。'),
                  _point(context, Icons.cloud_upload_outlined, 'AIアドバイスでは検査値と年齢・性別のみを外部のAIサービスへ送信します。'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: [
                CheckboxListTile(
                  value: _checked,
                  onChanged: (v) => setState(() => _checked = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('上記の内容を理解し、同意します'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _checked ? () => context.read<AppSettings>().setAgreed(true) : null,
                    child: const Text('同意して始める'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}
