import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/app_services.dart';
import 'services/database.dart';
import 'services/lab_catalog.dart';
import 'services/rule_engine.dart';
import 'services/settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    const secure = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(secure);
    final catalog = LabCatalog();
    catalog.load(custom: await db.customItems(), userRanges: await db.userRanges());
    final builtin = RuleSet.fromJsonString(await rootBundle.loadString(AppServices.rulesAsset));
    final custom = await db.getKv('rules_json');
    RuleSet rules = builtin;
    if (custom != null) {
      try {
        rules = RuleSet.fromJsonString(custom);
      } catch (_) {}
    }
    final settings = AppSettings(prefs, secure);
    final services = AppServices(db: db, catalog: catalog, settings: settings, rules: rules, builtinRules: builtin);
    await services.runAutoDelete();
    runApp(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: services),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: catalog),
      ],
      child: const LabSightApp(),
    ));
  } catch (e) {
    runApp(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('起動に失敗しました。\n端末の再起動後もこの表示が続く場合は、アプリを再インストールしてください。\n\n$e'),
          ),
        ),
      ),
    ));
  }
}
