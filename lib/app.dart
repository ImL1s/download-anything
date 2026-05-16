import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/pages/main_shell.dart';

class PmaApp extends StatelessWidget {
  const PmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Media Archiver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}
