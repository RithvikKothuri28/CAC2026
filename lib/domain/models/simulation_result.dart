import 'dart:math' as math;

/// The outcome distribution of one plan under thousands of simulated seasons.
///
/// Percentiles matter more than the mean here. A farm does not experience an
/// average year; it experiences one year, and the question that decides
/// whether it survives is how bad the bad ones get.
class SimulationResult {
  SimulationResult({
    required this.planLabel,
    required this.trials,
    required this.seed,
    required List<double> sortedSamples,
    required this.deterministicValue,
  }) : _sorted = List<double>.unmodifiable(sortedSamples);

  /// Which plan this distribution belongs to, e.g. `Current Plan`.
  final String planLabel;

  final int trials;

  /// The seed that produced this run. Re-running with it reproduces the
  /// distribution exactly.
  final int seed;

  /// Cash after debt service in each trial, ascending.
  ///
  /// Kept in memory for charting only. FarmTwin persists the summary
  /// statistics, never the individual samples.
  final List<double> _sorted;

  /// The engine's point estimate for the same plan, for reference against
  /// the simulated mean.
  final double deterministicValue;

  List<double> get samples => _sorted;

  double get mean {
    if (_sorted.isEmpty) return 0;
    double total = 0;
    for (final double v in _sorted) {
      total += v;
    }
    return total / _sorted.length;
  }

  double get median => percentile(50);

  double get standardDeviation {
    if (_sorted.length < 2) return 0;
    final double m = mean;
    double sumSquares = 0;
    for (final double v in _sorted) {
      final double d = v - m;
      sumSquares += d * d;
    }
    return math.sqrt(sumSquares / (_sorted.length - 1));
  }

  double get minimum => _sorted.isEmpty ? 0 : _sorted.first;
  double get maximum => _sorted.isEmpty ? 0 : _sorted.last;

  /// Linear-interpolated percentile, 0..100.
  double percentile(double p) {
    if (_sorted.isEmpty) return 0;
    if (_sorted.length == 1) return _sorted.first;
    final double clamped = p.clamp(0.0, 100.0).toDouble();
    final double position = (clamped / 100) * (_sorted.length - 1);
    final int lower = position.floor();
    final int upper = position.ceil();
    if (lower == upper) return _sorted[lower];
    final double weight = position - lower;
    return _sorted[lower] * (1 - weight) + _sorted[upper] * weight;
  }

  double get p5 => percentile(5);
  double get p25 => percentile(25);
  double get p75 => percentile(75);
  double get p95 => percentile(95);

  /// Share of trials finishing with cash left after debt service.
  double get probabilityPositive {
    if (_sorted.isEmpty) return 0;
    int count = 0;
    for (final double v in _sorted) {
      if (v > 0) count++;
    }
    return count / _sorted.length;
  }

  double get probabilityNegative => 1 - probabilityPositive;

  /// Probability that cash lands below [threshold] — the general form behind
  /// questions like "how likely am I to miss a $50,000 payment?".
  double probabilityBelow(double threshold) {
    if (_sorted.isEmpty) return 0;
    int count = 0;
    for (final double v in _sorted) {
      if (v < threshold) count++;
    }
    return count / _sorted.length;
  }

  /// Mean of the worst [tail] share of outcomes, e.g. `0.05` for the average
  /// of the worst 5% of years. Conditional shortfall answers "when it goes
  /// wrong, how wrong?", which a single percentile cannot.
  double expectedShortfall({double tail = 0.05}) {
    if (_sorted.isEmpty) return 0;
    final int count = math.max(1, (_sorted.length * tail).floor());
    double total = 0;
    for (int i = 0; i < count; i++) {
      total += _sorted[i];
    }
    return total / count;
  }

  /// Equal-width bucket counts for a histogram.
  List<int> histogram({int buckets = 30}) {
    final List<int> counts = List<int>.filled(buckets, 0);
    if (_sorted.isEmpty || buckets <= 0) return counts;
    final double low = minimum;
    final double high = maximum;
    final double span = high - low;
    if (span <= 0) {
      counts[0] = _sorted.length;
      return counts;
    }
    for (final double v in _sorted) {
      final int index = (((v - low) / span) * buckets).floor().clamp(
        0,
        buckets - 1,
      );
      counts[index]++;
    }
    return counts;
  }

  /// Summary suitable for persistence and for the assistant's context. The
  /// raw samples are deliberately excluded.
  Map<String, dynamic> toSummaryJson() => <String, dynamic>{
    'planLabel': planLabel,
    'trials': trials,
    'seed': seed,
    'deterministicValue': deterministicValue,
    'mean': mean,
    'median': median,
    'standardDeviation': standardDeviation,
    'p5': p5,
    'p25': p25,
    'p75': p75,
    'p95': p95,
    'minimum': minimum,
    'maximum': maximum,
    'probabilityPositive': probabilityPositive,
    'probabilityNegative': probabilityNegative,
    'expectedShortfall5': expectedShortfall(),
  };

  @override
  String toString() =>
      'SimulationResult($planLabel, n=$trials, '
      'median=${median.toStringAsFixed(0)}, '
      'P(+)=${(probabilityPositive * 100).toStringAsFixed(1)}%)';
}
