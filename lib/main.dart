import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app/config/app_config.dart';
import 'app/farmtwin_app.dart';
import 'app/theme/farm_theme.dart';
import 'core/logging/app_logger.dart';
import 'data/data.dart';
import 'data/firebase/firebase_connectivity_diagnostic.dart';
import 'features/workspace/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    final config = AppConfig.fromEnvironment();
    // Firebase and Auth are ready before the application can expose any forms.
    final cloud = await FirebaseBootstrap.initialize(config);
    final logger = SafeAppLogger(
      development: kDebugMode,
      reportError: cloud.privacy.recordError,
    );
    FlutterError.onError = (details) => logger.error(
      'flutter_framework',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    PlatformDispatcher.instance.onError = (failure, stack) {
      logger.error('unhandled_async', failure, stack);
      return true;
    };
    final diagnostic = FirebaseConnectivityDiagnostic(config);
    runApp(
      FarmTwinApp(
        workspace: WorkspaceController(
          cloud: cloud,
          connectivityDiagnostic: diagnostic.enabled ? diagnostic.run : null,
        ),
      ),
    );
  } catch (error) {
    runApp(_StartupFailure(message: error.toString()));
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FarmTwin',
    debugShowCheckedModeBanner: false,
    theme: FarmTheme.light,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.grass, size: 56, color: FarmTheme.forest),
              const SizedBox(height: 20),
              const Text('FarmTwin could not connect to Firebase.'),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: _start, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
  );
}
