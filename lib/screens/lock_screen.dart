import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';

/// パスコード・生体認証によるロック画面。
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _input = '';
  String? _error;
  int _failures = 0;
  DateTime? _blockedUntil;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<AppSettings>().biometricEnabled) _biometric();
    });
  }

  Future<void> _biometric() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return;
      final ok = await auth.authenticate(localizedReason: 'LabSight のロックを解除します', biometricOnly: true);
      if (ok && mounted) widget.onUnlocked();
    } catch (_) {
      // 生体認証が使えない場合はパスコードで解除
    }
  }

  Future<void> _submit() async {
    if (_input.isEmpty || _checking) return;
    final now = DateTime.now();
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      setState(() => _error = 'しばらく待ってから再入力してください（${_blockedUntil!.difference(now).inSeconds + 1}秒）');
      return;
    }
    setState(() => _checking = true);
    final ok = await context.read<AppSettings>().verifyPasscode(_input);
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      widget.onUnlocked();
      return;
    }
    _failures++;
    setState(() {
      _input = '';
      if (_failures >= 5) {
        _blockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
        _error = 'パスコードが違います。${30 * (_failures - 4)}秒後に再入力できます';
      } else {
        _error = 'パスコードが違います';
      }
    });
  }

  void _tap(String d) {
    if (_input.length >= 8) return;
    setState(() {
      _input += d;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bio = context.watch<AppSettings>().biometricEnabled;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, String? semantics}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 84,
            height: 72,
            child: Semantics(
              label: semantics ?? label,
              button: true,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                onPressed: onTap ?? () => _tap(label),
                child: icon != null ? Icon(icon, size: 28) : Text(label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                const SizedBox(height: 12),
                Text('LabSight', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('パスコードを入力してください'),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _input.isEmpty ? 4 : _input.length.clamp(4, 8),
                    (i) => Container(
                      margin: const EdgeInsets.all(6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _input.length ? scheme.primary : Colors.transparent,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: Center(child: Text(_error ?? '', style: TextStyle(color: scheme.error))),
                ),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  bio
                      ? key('', icon: Icons.fingerprint, onTap: _biometric, semantics: '生体認証')
                      : const SizedBox(width: 96),
                  key('0'),
                  key('', icon: Icons.backspace_outlined, semantics: '1文字消す', onTap: () {
                    if (_input.isNotEmpty) setState(() => _input = _input.substring(0, _input.length - 1));
                  }),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  child: FilledButton(
                    onPressed: _input.length >= 4 && !_checking ? _submit : null,
                    child: _checking ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('解除'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// パスコード設定ダイアログ（4–8桁の数字）。設定されたら true。
Future<bool> showSetPasscodeDialog(BuildContext context) async {
  final c1 = TextEditingController();
  final c2 = TextEditingController();
  String? error;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('パスコードの設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c1,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: const InputDecoration(labelText: '4〜8桁の数字'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: c2,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: InputDecoration(labelText: 'もう一度入力', errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () async {
              final a = c1.text.trim(), b = c2.text.trim();
              if (!RegExp(r'^\d{4,8}$').hasMatch(a)) {
                setState(() => error = '4〜8桁の数字で入力してください');
                return;
              }
              if (a != b) {
                setState(() => error = '一致しません');
                return;
              }
              await ctx.read<AppSettings>().setPasscode(a);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('設定'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
