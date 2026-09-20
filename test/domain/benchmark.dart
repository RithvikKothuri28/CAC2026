// Desktop profiling harness. Its output is measured, never bundled by the app.
// Run: dart run test/domain/benchmark.dart
import 'dart:convert';
import 'dart:io';
import 'package:farmtwin/domain/farm_domain.dart';

void main() {
  final farm = Farm.fromJson(
    jsonDecode(File('assets/sample/sample_farm.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final memoryBefore = ProcessInfo.currentRss;
  final optimization = const OptimizationEngine().run(farm);
  final selected = optimization.recommended!;
  final risk = const MonteCarloEngine().run(farm, selected.plan);
  final projectionWatch = Stopwatch()..start();
  final projection = const MultiYearEngine().compare(
    farm,
    farm.currentPlan,
    selected.plan,
  );
  projectionWatch.stop();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'platform': Platform.operatingSystem,
      'dartVersion': Platform.version,
      'measurement':
          'Single cold CLI run; does not measure mobile frames or startup.',
      'fields': farm.fields.length,
      'cropProfiles': farm.crops.length,
      'optimization': optimization.diagnostics.toJson(),
      'simulation': {
        'iterations': risk.iterations,
        'elapsedMicroseconds': risk.elapsedMicroseconds,
        'seed': risk.seed,
      },
      'fiveYear': {
        'years': projection.current.years.length,
        'elapsedMicroseconds': projectionWatch.elapsedMicroseconds,
      },
      'processMemory': {
        'beforeRssBytes': memoryBefore,
        'afterRssBytes': ProcessInfo.currentRss,
        'maxRssBytes': ProcessInfo.maxRss,
      },
    }),
  );
}
