import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/database.dart';
import '../services/pii.dart';
import '../widgets/common.dart';
import 'folder_detail_screen.dart';

class FolderListScreen extends StatefulWidget {
  const FolderListScreen({super.key});

  @override
  State<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends State<FolderListScreen> {
  String _q = '';

  Future<void> _create() async {
    final services = context.read<AppServices>();
    final name = await showFolderNameDialog(context, title: '新しいフォルダ');
    if (name == null) return;
    await services.db.saveFolder(Folder(name: name));
    services.dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppServices>();
    return Scaffold(
      appBar: AppBar(title: const Text('フォルダ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新規フォルダ'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'フォルダ名で検索'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: services.dataVersion,
              builder: (context, _, _) => FutureBuilder<List<Folder>>(
                future: services.db.folders(),
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final list = snap.data!.where((f) => _q.isEmpty || f.name.contains(_q) || f.memo.contains(_q)).toList();
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('フォルダがありません。\n患者/ケースごとにフォルダを作成し、採血データを日時ごとに保存できます。', textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final f = list[i];
                      return Card(
                        child: ListTile(
                          minVerticalPadding: 14,
                          leading: const Icon(Icons.folder_outlined, size: 30),
                          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                          subtitle: Text([
                            '${f.setCount}件',
                            if (f.lastTakenAt != null) '最終採血 ${dateTimeFmt.format(f.lastTakenAt!)}',
                            if (f.memo.isNotEmpty) f.memo,
                          ].join('・')),
                          trailing: IconButton(
                            tooltip: '削除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteFolderWithConfirm(context, f),
                          ),
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => FolderDetailScreen(folderId: f.id))),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> deleteFolderWithConfirm(BuildContext context, Folder f) async {
  final services = context.read<AppServices>();
  final ok = await confirmDialog(context,
      title: 'フォルダを削除',
      message: '「${f.name}」と、中の採血データ ${f.setCount}件・評価履歴・AIの会話をすべて削除します。元に戻せません。');
  if (!ok) return false;
  await services.db.deleteFolder(f.id);
  services.dataChanged();
  if (context.mounted) showSnack(context, '削除しました');
  return true;
}

Future<String?> showFolderNameDialog(BuildContext context, {required String title, String initial = ''}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'フォルダ名',
          hintText: '例: 3階 12床、ケースA',
          helperText: '氏名・IDなどは自動で削除します',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            final t = c.text.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
  if (r == null || !context.mounted) return r;
  final clean = cleanPersonalInfo(context, r).trim();
  return clean.isEmpty || clean == piiMark ? AppDatabase.safeFolderName('', DateTime.now()) : clean;
}
