import 'dart:math' as math;

import '../models/crop_allocation.dart';
import '../models/crop_profile.dart';
import '../models/farm.dart';
import '../models/farm_field.dart';
import 'constraint_engine.dart';

/// The pruned search space for one optimisation run.
///
/// Candidates are addressed by integer index using mixed-radix decoding, so
/// the generator never materialises the full list of plans in memory — it can
/// hand out plan number 9,412 directly.
class CandidateSpace {
  CandidateSpace({
    required this.fields,
    required this.optionsByField,
    required this.allocationSpace,
    required this.enumerableCount,
    required this.fieldsWithNoOptions,
  });

  /// Fields in stable sorted order; option lists are aligned to this.
  final List<FarmField> fields;

  /// Crops still permitted on each field after per-field pruning.
  final List<List<String>> optionsByField;

  /// `crops ^ fields` before any pruning — the theoretical space.
  final int allocationSpace;

  /// Plans actually reachable after pruning.
  final int enumerableCount;

  /// Fields that no crop can legally occupy. Any such field makes the whole
  /// space empty, and naming them is what lets the UI explain why.
  final List<String> fieldsWithNoOptions;

  int get prunedCount {
    final int pruned = allocationSpace - enumerableCount;
    return pruned > 0 ? pruned : 0;
  }

  bool get isEmpty => enumerableCount <= 0;

  /// Decodes a candidate index into an allocation.
  ///
  /// The index is read as a mixed-radix number, one digit per field, with
  /// each field's radix being its own option count.
  CropAllocation allocationAt(int index) {
    final Map<String, String> byField = <String, String>{};
    int remaining = index;
    for (int i = 0; i < fields.length; i++) {
      final List<String> options = optionsByField[i];
      final int radix = options.length;
      final int digit = remaining % radix;
      remaining ~/= radix;
      byField[fields[i].id] = options[digit];
    }
    return CropAllocation(byField);
  }

  /// The index of an existing allocation, or null when it lies outside the
  /// pruned space — which is exactly what happens when the farm's current
  /// plan breaks one of its own agronomic rules.
  int? indexOf(CropAllocation allocation) {
    int index = 0;
    int multiplier = 1;
    for (int i = 0; i < fields.length; i++) {
      final String? cropId = allocation.cropFor(fields[i].id);
      if (cropId == null) return null;
      final int digit = optionsByField[i].indexOf(cropId);
      if (digit < 0) return null;
      index += digit * multiplier;
      multiplier *= optionsByField[i].length;
    }
    return index;
  }
}

/// Builds the space of candidate farm plans.
///
/// Pruning happens before enumeration, not after. A crop that cannot legally
/// sit on a field is removed from that field's option list, which removes
/// every plan containing that pairing at once — for the demo farm that is
/// roughly 89% of the space eliminated without costing a single plan.
class CandidateGenerator {
  const CandidateGenerator({this.constraints = const ConstraintEngine()});

  final ConstraintEngine constraints;

  /// Applies per-field pruning and reports the resulting space.
  CandidateSpace prepare(Farm farm) {
    final bool enforceRotation = constraints.rotationIsHard(farm);
    final Set<String> restrictedTags = constraints.hardRestrictedTags(farm);

    final List<List<String>> optionsByField = <List<String>>[];
    final List<String> emptyFields = <String>[];

    for (final FarmField field in farm.fields) {
      final List<String> allowed = <String>[];
      for (final CropProfile crop in farm.cropProfiles) {
        if (constraints.isPairingAllowed(
          farm: farm,
          field: field,
          crop: crop,
          enforceRotation: enforceRotation,
          restrictedTags: restrictedTags,
        )) {
          allowed.add(crop.id);
        }
      }
      if (allowed.isEmpty) emptyFields.add(field.id);
      optionsByField.add(allowed);
    }

    return CandidateSpace(
      fields: farm.fields,
      optionsByField: optionsByField,
      allocationSpace: _power(farm.cropProfiles.length, farm.fields.length),
      enumerableCount: _product(
        optionsByField.map((List<String> o) => o.length),
      ),
      fieldsWithNoOptions: emptyFields,
    );
  }

  /// Candidate indices to evaluate.
  ///
  /// Below [maxCandidates] every plan is enumerated, so the result is a true
  /// exhaustive search. Above it the generator draws a seeded random sample
  /// instead — still reproducible, but the run reports that it sampled rather
  /// than claiming an exhaustive result it did not perform.
  List<int> candidateIndices({
    required CandidateSpace space,
    required int maxCandidates,
    required int seed,
    CropAllocation? alwaysInclude,
  }) {
    if (space.isEmpty) return const <int>[];

    if (space.enumerableCount <= maxCandidates) {
      return List<int>.generate(space.enumerableCount, (int i) => i);
    }

    final math.Random random = math.Random(seed);
    final Set<int> sampled = <int>{};

    final int? pinned = alwaysInclude == null
        ? null
        : space.indexOf(alwaysInclude);
    if (pinned != null) sampled.add(pinned);

    // Draw until the quota is met. Rejection sampling is safe here because
    // maxCandidates is far below enumerableCount whenever this path runs.
    while (sampled.length < maxCandidates) {
      sampled.add(random.nextInt(space.enumerableCount));
    }

    final List<int> indices = sampled.toList()..sort();
    return indices;
  }

  /// `base ^ exponent`, saturating instead of overflowing.
  ///
  /// A farm large enough to overflow a 64-bit count is reported at the cap;
  /// the sampling path then keeps the run tractable regardless.
  static int _power(int base, int exponent) {
    if (base <= 0 || exponent <= 0) return 0;
    const int ceiling = 1 << 62;
    int result = 1;
    for (int i = 0; i < exponent; i++) {
      if (result > ceiling ~/ base) return ceiling;
      result *= base;
    }
    return result;
  }

  static int _product(Iterable<int> values) {
    const int ceiling = 1 << 62;
    int result = 1;
    for (final int value in values) {
      if (value <= 0) return 0;
      if (result > ceiling ~/ value) return ceiling;
      result *= value;
    }
    return result;
  }
}
