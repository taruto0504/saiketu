import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/clinical_calc.dart';
import '../services/lab_catalog.dart';
import '../widgets/common.dart';
import 'capture_flow.dart';
import 'compare_screen.dart';
import 'folder_list_screen.dart';
import 'result_screen.dart';

/// フォルダ詳細（採血日時ごとのデータ一覧）。
class FolderDetailScreen extends StatelessWidget {
  const FolderDetailScreen({super.key, required this.folderId});
  final String folderId;

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppServices>();
    return ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => FutureBuilder<(Folder?, List<LabSet>)>(
        future: () async {
          final folders = await services.db.folders();
          final f = folders.where((x) => x.id == folderId).firstOrNull;
          return (f, f == null ? <LabSet>[] : await services.db.labSets(folderId));
        }(),
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final (folder, sets) = snap.data!;
          if (folder == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: Text('フォルダが見つかりません')));
          }
          final desc = sets.reversed.toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(folder.name),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (k) async {
                    if (k == 'rename') {
                      final n = await showFolderNameDialog(context, title: 'フォルダ名の変更', initial: folder.name);
                      if (n != null) {
                        folder.name = n;
                        await services.db.saveFolder(folder);
                        services.dataChanged();
                      }
                    } else if (k == 'memo') {
                      final c = TextEditingController(text: folder.memo);
                      final m = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('メモ'),
                          content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: '個人情報は入力しないでください')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('保存')),
                          ],
                        ),
                      );
                      if (m != null) {
                        folder.memo = m;
                        await services.db.saveFolder(folder);
                        services.dataChanged();
                      }
                    } else if (k == 'delete') {
                      if (await deleteFolderWithConfirm(context, folder) && context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('名前を変更')),
                    PopupMenuItem(value: 'memo', child: Text('メモを編集')),
                    PopupMenuItem(value: 'delete', child: Text('フォルダを削除')),
                  ],
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (folder.memo.isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(folder.memo)),
                SectionHeader('採血データ（${sets.length}件）', icon: Icons.event_note),
                if (sets.isEmpty)
                  const Padding(padding: EdgeInsets.all(20), child: Text('データがありません。下のボタンから追加してください。')),
                for (final s in desc) _SetTile(set: s),
              ],
            ),
            bottomNavigationBar: BottomActions(children: [
              OutlinedButton.icon(
                onPressed: () => _addData(context),
                icon: const Icon(Icons.add),
                label: const Text('データ追加'),
              ),
              FilledButton.icon(
                onPressed: sets.length >= 2
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompareScreen(folderId: folderId)))
                    : null,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('比較・推移'),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _addData(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('カメラで読み取る'),
            onTap: () {
              Navigator.pop(ctx);
              startCapture(context, CaptureSource.camera, folderId: folderId);
            },
          ),
          ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('写真から読み取る'),
            onTap: () {
              Navigator.pop(ctx);
              startCapture(context, CaptureSource.photo, folderId: folderId);
            },
          ),
          ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.edit_note),
            title: const Text('手入力'),
            onTap: () {
              Navigator.pop(ctx);
              startCapture(context, CaptureSource.manual, folderId: folderId);
            },
          ),
        ]),
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  const _SetTile({required this.set});
  final LabSet set;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final services = context.read<AppServices>();
    final spec = effectiveSpecimen(set);
    var abnormal = 0, critical = 0;
    for (final v in set.values) {
      final f = catalog.flagFor(v, sex: set.context.sex, specimen: spec);
      if (f.isAbnormal) abnormal++;
      if (f.isCritical) critical++;
    }
    final lab = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(critical > 0 ? Icons.warning_rounded : Icons.description_outlined,
            color: critical > 0 ? lab.error : lab.primary, semanticLabel: critical > 0 ? '危険値あり' : null),
        title: Text(dateTimeFmt.format(set.takenAt), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
        subtitle: Text([
          '${set.values.length}項目',
          '異常 $abnormal',
          if (critical > 0) '危険値 $critical',
          switch (set.source) { 'camera' => 'カメラ', 'photo' => '写真', _ => '手入力' },
          if (!set.context.isEmpty) '追加情報あり',
        ].join('・')),
        trailing: IconButton(
          tooltip: 'このデータを削除',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await confirmDialog(context,
                title: 'データを削除', message: '${dateTimeFmt.format(set.takenAt)} の採血データ（評価履歴・AIの会話を含む）を削除します。元に戻せません。');
            if (!ok) return;
            await services.db.deleteLabSet(set.id);
            services.dataChanged();
          },
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(set: set))),
      ),
    );
  }
}
