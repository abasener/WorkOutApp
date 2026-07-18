import 'package:flutter/material.dart';

import 'screens/root_shell.dart';
import 'services/app_services.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppServices.init();
  await NotificationService.init();
  runApp(const TerpinLiftApp());
}

class TerpinLiftApp extends StatelessWidget {
  const TerpinLiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerpinLift',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootShell(),
    );
  }
}
