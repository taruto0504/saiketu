import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import 'capture_flow.dart';
import 'folder_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenFolders});
  final VoidCallback onOpenFolders;

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppServices>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.biotech_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          Text('LabSight', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 8),
          _BigButton(
            icon: Icons.document_scanner_outlined,
            title: 'カメラで読み取る',
            subtitle: '検査用紙・画面を自動検出して撮影',
            primary: true,
            onTap: () => startCapture(context, CaptureSource.camera),
          ),
          _BigButton(
            icon: Icons.photo_library_outlined,
            title: '写真から読み取る',
            subtitle: 'アルバムの写真・スクリーンショット',
            onTap: () => startCapture(context, CaptureSource.photo),
          ),
          _BigButton(
            icon: Icons.edit_note,
            title: '手入力',
            subtitle: '項目を選んで数値を入力',
            onTap: () => startCapture(context, CaptureSource.manual),
          ),
          SectionHeader('最近のフォルダ',
              icon: Icons.history,
              trailing: TextButton(onPressed: onOpenFolders, child: const Text('すべて表示'))),
          ValueListenableBuilder<int>(
            valueListenable: services.dataVersion,
            builder: (context, _, _) => FutureBuilder<List<Folder>>(
              future: services.db.folders(),
              builder: (context, snap) {
                final list = snap.data ?? const [];
                if (snap.connectionState != ConnectionState.done && list.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                }
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('まだ保存されたデータはありません。読み取り後に「保存」するとフォルダに整理されます。'),
                  );
                }
                return Column(
                  children: [
                    for (final f in list.take(5))
                      Card(
                        child: ListTile(
                          minVerticalPadding: 14,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${f.setCount}件'
                              '${f.lastTakenAt != null ? '・最終採血 ${dateTimeFmt.format(f.lastTakenAt!)}' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => FolderDetailScreen(folderId: f.id))),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.wifi_off, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text('読み取り・判定は端末内で行います（AIアドバイスのみ通信を使用）',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.title, required this.subtitle, required this.onTap, this.primary = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = primary ? scheme.primary : scheme.surface;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: primary
                ? null
                : BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
            child: Row(
              children: [
                Icon(icon, size: 40, color: primary ? fg : scheme.primary),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
