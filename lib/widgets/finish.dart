import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/app_services.dart';
import 'common.dart';
import 'pickers.dart';

/// 疾患推定・AI・情報追加を終えて、最初の画面に戻る。保存していない結果なら、保存するか確認する。
Future<void> finishFlow(BuildContext context, LabSet set) async {
  void done() => Navigator.of(context).popUntil((r) => r.isFirst);
  if (set.isSaved) return done();
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('終了しますか？'),
      content: const Text('この結果はまだ保存していません。保存しないで終了すると、結果は消えます。'),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('保存せずに終了')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('保存して終了')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'save') {
    final f = await showFolderPicker(context);
    if (f == null || !context.mounted) return;
    final services = context.read<AppServices>();
    set.folderId = f.id;
    for (final v in set.values) {
      v.uncertain = false;
      v.warnings.clear();
      v.rawText = null;
    }
    await services.db.saveLabSet(set);
    services.dataChanged();
    services.settings.stats.track('set_saved');
    if (!context.mounted) return;
    showSnack(context, '「${f.name}」に保存しました');
  }
  done();
}
