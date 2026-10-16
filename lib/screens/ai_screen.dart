import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/lab_set.dart';
import '../services/ai_service.dart';
import '../services/app_services.dart';
import '../services/settings.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

/// AIアドバイス（オンライン時のみ）。
class AiScreen extends StatefulWidget {
  const AiScreen({super.key, required this.set, this.previous});
  final LabSet set;
  final LabSet? previous;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  bool _online = false;
  bool _hasKey = false;
  bool _busy = false;
  String? _error;
  StreamSubscription<bool>? _sub;

  /// 画面表示用の会話（role/content）。最初の user は検査データの要約。
  final List<Map<String, String>> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final services = context.read<AppServices>();
    _online = await Connectivity2.check();
    _hasKey = (await services.settings.apiKey()) != null;
    _sub = Connectivity2.watch().listen((v) {
      if (mounted) setState(() => _online = v);
    });
    if (widget.set.isSaved) {
      _messages.addAll(await services.db.aiChat(widget.set.id));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _buildSummary() {
    final services = context.read<AppServices>();
    final eval = AiService.privacySafeEvaluation(services.engine, widget.set, widget.previous);
    return AiService.buildLabSummary(
      catalog: services.catalog,
      current: widget.set,
      previous: widget.previous,
      evaluation: eval,
    );
  }

  Future<void> _send(List<Map<String, String>> next) async {
    final services = context.read<AppServices>();
    final key = await services.settings.apiKey();
    if (key == null) {
      setState(() => _error = 'APIキーが設定されていません');
      return;
    }
    services.settings.stats.track(next.length == 1 ? 'ai_advice' : 'ai_chat');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await services.ai.send(apiKey: key, model: services.settings.aiModel, messages: next);
      _messages
        ..clear()
        ..addAll(next)
        ..add({'role': 'assistant', 'content': reply});
      if (widget.set.isSaved) await services.db.saveAiChat(widget.set.id, _messages);
    } on AiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _generate() async {
    final summary = _buildSummary();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('送信内容の確認'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('以下の内容のみを外部のAIサービス（Anthropic Claude API）へ送信します。氏名・ID・フォルダ名・日付・自由記載は送信しません。'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                child: Text(summary, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('送信する')),
        ],
      ),
    );
    if (ok != true) return;
    await _send([
      {'role': 'user', 'content': '$summary\n\n${AiService.initialRequest}'},
    ]);
  }

  Future<void> _ask() async {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    final warn = personalInfoWarning(q);
    if (warn != null) {
      final go = await confirmDialog(context, title: '個人情報の確認', message: '$warn\nこのまま送信しますか？', ok: '送信する', destructive: false);
      if (!go) return;
    }
    _input.clear();
    await _send([
      ..._messages,
      {'role': 'user', 'content': q},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final canUse = _online && _hasKey && !_busy;
    final started = _messages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIアドバイス'),
        actions: [
          if (started)
            IconButton(
              tooltip: 'やり直す',
              icon: const Icon(Icons.restart_alt),
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await confirmDialog(context, title: '会話をリセット', message: 'AIとの会話を消去して最初から生成しますか？', ok: 'リセット');
                      if (!ok) return;
                      setState(_messages.clear);
                      if (widget.set.isSaved && context.mounted) {
                        await context.read<AppServices>().db.saveAiChat(widget.set.id, []);
                      }
                    },
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_online)
            _Banner(icon: Icons.wifi_off, text: 'オフラインのためAI機能は使えません。端末内の判定（疾患推定）は利用できます。', color: scheme.errorContainer),
          if (_online && !_hasKey)
            _Banner(
              icon: Icons.key_outlined,
              text: 'APIキーが未設定です。設定画面で入力してください。',
              color: scheme.secondaryContainer,
              action: TextButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeyScreen()));
                  _hasKey = (await settings.apiKey()) != null;
                  if (mounted) setState(() {});
                },
                child: const Text('設定'),
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                if (!started)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('端末内の判定結果と根拠をAIに渡し、病態整理・追加検査・注意点・前回からの変化の解釈を解説させます。',
                          style: TextStyle(fontSize: 15)),
                      const SizedBox(height: 8),
                      Text('送信するのは検査値と年齢・性別のみです（モデル: ${settings.aiModel}）。',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: canUse ? _generate : null,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('AIアドバイスを生成'),
                        ),
                      ),
                    ]),
                  ),
                for (final (i, m) in _messages.indexed)
                  if (i > 0 || m['role'] != 'user')
                    _Bubble(text: m['content']!, isUser: m['role'] == 'user')
                  else
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text('検査データと判定結果を送信しました', style: TextStyle(fontSize: 12)),
                    ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(children: [
                      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      SizedBox(width: 12),
                      Text('AIが回答を作成中…（1分程度かかることがあります）'),
                    ]),
                  ),
                if (_error != null)
                  _Banner(icon: Icons.error_outline, text: _error!, color: scheme.errorContainer),
                const DisclaimerFooter(),
              ],
            ),
          ),
          if (started)
            Material(
              elevation: 8,
              color: scheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: canUse,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: canUse ? '追加で質問する（個人情報は入力しない）' : 'オフライン・未設定のため使用できません',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      iconSize: 26,
                      style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                      onPressed: canUse ? _ask : null,
                      icon: const Icon(Icons.send),
                      tooltip: '送信',
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color, this.action});
  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          ?action,
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.8 : 0.95)),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: isUser ? null : Border.all(color: scheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isUser)
            Row(children: [
              Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
              const SizedBox(width: 4),
              Text('AI（参考情報）', style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  showSnack(context, 'コピーしました');
                },
                child: Icon(Icons.copy, size: 16, color: scheme.onSurfaceVariant),
              ),
            ]),
          SelectableText(_plain(text), style: const TextStyle(height: 1.55, fontSize: 15)),
        ]),
      ),
    );
  }

  /// Markdown の見出し記号などを簡易的に整形。
  static String _plain(String s) => s
      .replaceAllMapped(RegExp(r'^#{1,6}\s*(.*)$', multiLine: true), (m) => '■ ${m[1]}')
      .replaceAll('**', '')
      .replaceAllMapped(RegExp(r'^(\s*)[-*]\s+', multiLine: true), (m) => '${m[1]}・');
}
