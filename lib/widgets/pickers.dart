import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_item.dart';
import '../models/lab_set.dart';
import '../services/app_services.dart';
import '../services/lab_catalog.dart';
import 'common.dart';

/// 検査項目の選択（別名でも検索可）。
Future<LabItemDef?> showItemPicker(BuildContext context, {Set<String> exclude = const {}}) {
  return showModalBottomSheet<LabItemDef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ItemPicker(exclude: exclude),
  );
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.exclude});
  final Set<String> exclude;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<LabCatalog>();
    final q = normalizeName(_q);
    final items = catalog.all.where((i) {
      if (widget.exclude.contains(i.code)) return false;
      if (q.isEmpty) return true;
      return [i.code, i.name, i.jpName, ...i.aliases].any((a) => normalizeName(a).contains(q));
    }).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '項目名・別名で検索（例: Cr, クレアチニン）'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final it = items[i];
                final showHeader = i == 0 || items[i - 1].category != it.category;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader) SectionHeader(it.category.label),
                    ListTile(
                      title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${it.jpName}${it.unit.isEmpty ? '' : '（${it.unit}）'}'),
                      onTap: () => Navigator.pop(ctx, it),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 保存先フォルダの選択（新規作成可）。
Future<Folder?> showFolderPicker(BuildContext context) {
  return showModalBottomSheet<Folder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _FolderPicker(),
  );
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker();

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  final _name = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SectionHeader('保存先フォルダ', icon: Icons.folder_outlined),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '新しいフォルダ名',
                      hintText: 'ID・イニシャル・メモ名など（氏名は避けてください）',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final n = _name.text.trim();
                    if (n.isEmpty) return;
                    final f = Folder(name: n);
                    await services.db.saveFolder(f);
                    services.dataChanged();
                    if (context.mounted) Navigator.pop(context, f);
                  },
                  child: const Text('作成'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<Folder>>(
                future: services.db.folders(),
                builder: (ctx, snap) {
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const Center(child: Text('既存のフォルダはありません'));
                  }
                  return ListView(
                    children: [
                      for (final f in list)
                        ListTile(
                          minVerticalPadding: 14,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(f.name),
                          subtitle: Text('${f.setCount}件'),
                          onTap: () => Navigator.pop(ctx, f),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
