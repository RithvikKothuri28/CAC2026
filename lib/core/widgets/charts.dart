import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/farm_theme.dart';
import '../../domain/farm_domain.dart';
import 'components.dart';

class FarmCanvas extends StatelessWidget {
  const FarmCanvas({super.key, required this.farm, this.plan, this.onField});
  final Farm farm;
  final FarmPlan? plan;
  final void Function(Field)? onField;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, size) {
          final columns = size.maxWidth > 500 ? 3 : 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: farm.fields.map((field) {
              final cropId = (plan ?? farm.currentPlan).assignments[field.id]!;
              final crop = farm.crop(cropId);
              final color =
                  FarmTheme.cropColors[farm.crops.indexWhere(
                        (c) => c.id == cropId,
                      ) %
                      FarmTheme.cropColors.length];
              final changed = cropId != field.currentCropId;
              return SizedBox(
                width: (size.maxWidth - (columns - 1) * 10) / columns,
                child: Material(
                  color: color.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onField == null ? null : () => onField!(field),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 118),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: color, width: 5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  field.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (changed)
                                const Icon(Icons.swap_horiz, size: 17),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(crop.name),
                          Text(
                            '${number(field.acres)} acres',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
      const SizedBox(height: 14),
      Text(
        'Field schematic · tiles are not geographic boundaries',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class TradeoffChart extends StatelessWidget {
  const TradeoffChart({
    super.key,
    required this.plans,
    required this.current,
    this.selected,
    required this.onSelect,
  });
  final List<EvaluatedPlan> plans;
  final EvaluatedPlan current;
  final EvaluatedPlan? selected;
  final ValueChanged<EvaluatedPlan> onSelect;
  @override
  Widget build(BuildContext context) {
    final all = [...plans, current];
    final xs = all.map((p) => p.financial.waterUsage);
    final ys = all.map((p) => p.financial.operatingIncome);
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final spanX = maxX == minX ? 1.0 : maxX - minX;
    final spanY = maxY == minY ? 1.0 : maxY - minY;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Expected operating income ↑'),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: LayoutBuilder(
            builder: (context, size) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < 5; i++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: i * 55 + 12,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 65,
                          child: Text(
                            NumberAbbreviation.format(maxY - spanY * i / 4),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Expanded(child: Divider(color: FarmTheme.line)),
                      ],
                    ),
                  ),
                for (final plan in all)
                  Positioned(
                    left:
                        65 +
                        (plan.financial.waterUsage - minX) /
                            spanX *
                            (size.maxWidth - 98),
                    top:
                        12 +
                        (maxY - plan.financial.operatingIncome) / spanY * 220 -
                        10,
                    child: Tooltip(
                      message:
                          '${number(plan.financial.waterUsage)} acre-ft · ${number(plan.financial.operatingIncome)} income',
                      child: Semantics(
                        button: plan != current,
                        label:
                            'Plan with ${number(plan.financial.waterUsage)} acre feet and ${number(plan.financial.operatingIncome)} income',
                        child: GestureDetector(
                          onTap: plan == current ? null : () => onSelect(plan),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: plan == current
                                  ? FarmTheme.amber
                                  : plan == selected
                                  ? FarmTheme.forest
                                  : FarmTheme.moss.withValues(alpha: .75),
                              shape: plan == current
                                  ? BoxShape.rectangle
                                  : BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: plan == selected
                                  ? [
                                      const BoxShadow(
                                        color: FarmTheme.moss,
                                        blurRadius: 7,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 65,
                  bottom: 0,
                  child: Text(
                    number(minX),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    number(maxX),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text(
                '■ Current   ● Efficient alternatives',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Text(
              'Water use (acre-ft) →',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

abstract final class NumberAbbreviation {
  static String format(double value) => value.abs() >= 1000000
      ? '${number(value / 1000000)}m'
      : value.abs() >= 1000
      ? '${number(value / 1000)}k'
      : number(value);
}

class DistributionChart extends StatelessWidget {
  const DistributionChart({super.key, required this.current, this.alternative});
  final MonteCarloResult current;
  final MonteCarloResult? alternative;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 220,
        width: double.infinity,
        child: CustomPaint(painter: _DistributionPainter(current, alternative)),
      ),
      const SizedBox(height: 12),
      const Text('Cash after debt service →'),
      const SizedBox(height: 10),
      const Text(
        'Current: amber   •   Selected plan: green',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}

class _DistributionPainter extends CustomPainter {
  _DistributionPainter(this.current, this.alternative);
  final MonteCarloResult current;
  final MonteCarloResult? alternative;
  @override
  void paint(Canvas canvas, Size size) {
    final samples = [...current.samples, ...?alternative?.samples];
    if (samples.isEmpty) return;
    final lower = samples.reduce(math.min), upper = samples.reduce(math.max);
    final span = upper == lower ? 1.0 : upper - lower;
    const binCount = 30;
    List<int> bins(List<double> values) {
      final output = List<int>.filled(binCount, 0);
      for (final value in values) {
        output[((value - lower) / span * binCount).floor().clamp(
          0,
          binCount - 1,
        )]++;
      }
      return output;
    }

    final a = bins(current.samples),
        b = alternative == null
            ? List<int>.filled(binCount, 0)
            : bins(alternative!.samples);
    final maxCount = [...a, ...b].reduce(math.max).toDouble();
    final chartHeight = size.height - 25;
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(0, chartHeight * i / 4),
        Offset(size.width, chartHeight * i / 4),
        Paint()..color = FarmTheme.line,
      );
    }
    for (var i = 0; i < binCount; i++) {
      final w = size.width / binCount;
      canvas.drawRect(
        Rect.fromLTWH(
          i * w,
          chartHeight - a[i] / maxCount * chartHeight,
          w - 1,
          a[i] / maxCount * chartHeight,
        ),
        Paint()..color = FarmTheme.amber.withValues(alpha: .5),
      );
      canvas.drawRect(
        Rect.fromLTWH(
          i * w,
          chartHeight - b[i] / maxCount * chartHeight,
          w - 1,
          b[i] / maxCount * chartHeight,
        ),
        Paint()..color = FarmTheme.forest.withValues(alpha: .6),
      );
    }
    if (lower < 0 && upper > 0) {
      final zeroX = -lower / span * size.width;
      canvas.drawLine(
        Offset(zeroX, 0),
        Offset(zeroX, chartHeight),
        Paint()
          ..color = FarmTheme.danger
          ..strokeWidth = 2,
      );
    }
    void label(String value, double x) {
      final text = TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(color: FarmTheme.muted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(
          x.clamp(0, math.max(0, size.width - text.width)),
          chartHeight + 8,
        ),
      );
    }

    label(NumberAbbreviation.format(lower), 0);
    label(NumberAbbreviation.format(upper), size.width);
  }

  @override
  bool shouldRepaint(_DistributionPainter old) =>
      old.current != current || old.alternative != alternative;
}
