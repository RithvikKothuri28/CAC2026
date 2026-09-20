import 'dart:ui';
import 'package:flutter/material.dart';
import 'app/config/app_config.dart';
import 'app/farmtwin_app.dart';
import 'app/theme/farm_theme.dart';
import 'core/logging/app_logger.dart';
import 'data/data.dart';
import 'features/workspace/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();
  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  WorkspaceController? workspace;
  String? error;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    setState(() => error = null);
    try {
      FirebaseServices? cloud;
      String? cloudError;
      var development = false;
      try {
        final config = AppConfig.fromEnvironment();
        development = config.isDevelopment;
        cloud = await FirebaseBootstrap.initialize(config);
      } catch (failure) {
        cloudError = failure.toString();
      }
      final logger = SafeAppLogger(
        development: development,
        reportError: cloud?.privacy.recordError,
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
      if (mounted) {
        setState(
          () => workspace = WorkspaceController(
            sampleRepository: null,
            cloud: cloud,
            startupError: cloudError,
          ),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    }
  }

  @override
  void dispose() {
    workspace?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (workspace != null) return FarmTwinApp(workspace: workspace!);
    return MaterialApp(
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
                if (error == null)
                  const CircularProgressIndicator()
                else ...[
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: initialize,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
