import 'package:farmtwin/domain/engines/candidate_generator.dart';
import 'package:farmtwin/domain/models/crop_allocation.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/farm_constraint.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

void main() {
  const CandidateGenerator generator = CandidateGenerator();

  group('pruning', () {
    test('the demo farm prunes 15,625 allocations down to 1,728', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      // Six fields, five crops.
      expect(space.allocationSpace, 15625);
      expect(space.enumerableCount, 1728);
      expect(space.prunedCount, 13897);
      expect(space.fieldsWithNoOptions, isEmpty);
    });

    test('every surviving option is legal on its field', () {
      final Farm farm = loadDemoFarm();
      final CandidateSpace space = generator.prepare(farm);

      for (int i = 0; i < space.fields.length; i++) {
        final String fieldId = space.fields[i].id;
        final List<String> options = space.optionsByField[i];

        expect(options, isNotEmpty, reason: '$fieldId has no options');

        if (!space.fields[i].irrigated) {
          expect(
            options,
            isNot(contains('alfalfa')),
            reason: 'alfalfa needs irrigation, $fieldId has none',
          );
        }
        if (space.fields[i].soilType == 'sandy loam') {
          expect(
            options,
            isNot(contains('alfalfa')),
            reason: 'alfalfa will not hold on sandy loam',
          );
        }
      }
    });

    test('rotation pruning removes the crop grown last season', () {
      final Farm farm = loadDemoFarm();
      final CandidateSpace space = generator.prepare(farm);

      final int northIndex = space.fields.indexWhere(
        (dynamic f) => f.id == 'f_north_quarter',
      );
      expect(space.optionsByField[northIndex], isNot(contains('corn')));
    });

    test('rotation is only pruned when the farmer made it a hard rule', () {
      final Farm farm = loadDemoFarm();
      final Farm soft = farm.copyWith(
        constraints: farm.constraints
            .map(
              (FarmConstraint c) => c.type == ConstraintType.rotationRequired
                  ? c.copyWith(mode: ConstraintMode.preference)
                  : c,
            )
            .toList(),
      );

      final CandidateSpace space = generator.prepare(soft);
      final int northIndex = space.fields.indexWhere(
        (dynamic f) => f.id == 'f_north_quarter',
      );

      // With rotation demoted to a preference, corn on North Quarter becomes
      // a scored tradeoff rather than an excluded plan.
      expect(space.optionsByField[northIndex], contains('corn'));
      expect(space.enumerableCount, greaterThan(1728));
    });
  });

  group('index decoding', () {
    test('every index decodes to a complete, legal allocation', () {
      final Farm farm = loadDemoFarm();
      final CandidateSpace space = generator.prepare(farm);

      for (int i = 0; i < space.enumerableCount; i++) {
        final CropAllocation allocation = space.allocationAt(i);
        expect(allocation.fieldCount, farm.fields.length);

        for (int f = 0; f < space.fields.length; f++) {
          final String? crop = allocation.cropFor(space.fields[f].id);
          expect(crop, isNotNull);
          expect(space.optionsByField[f], contains(crop));
        }
      }
    });

    test('indices map one-to-one onto distinct allocations', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      final Set<String> signatures = <String>{};
      for (int i = 0; i < space.enumerableCount; i++) {
        signatures.add(space.allocationAt(i).signature);
      }

      expect(signatures, hasLength(space.enumerableCount));
    });

    test('indexOf round-trips an allocation back to its index', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      for (final int index in <int>[0, 1, 417, 1000, 1727]) {
        expect(space.indexOf(space.allocationAt(index)), index);
      }
    });

    test('an allocation outside the pruned space has no index', () {
      final Farm farm = loadDemoFarm();
      final CandidateSpace space = generator.prepare(farm);

      // The farm's own plan puts corn on North Quarter two years running,
      // which pruning removed — so the baseline is deliberately unreachable
      // by the search.
      expect(space.indexOf(farm.currentAllocation), isNull);
    });
  });

  group('enumeration versus sampling', () {
    test('a space under the cap is enumerated exhaustively', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      final List<int> indices = generator.candidateIndices(
        space: space,
        maxCandidates: 250000,
        seed: 1,
      );

      expect(indices, hasLength(space.enumerableCount));
      expect(indices.first, 0);
      expect(indices.last, space.enumerableCount - 1);
    });

    test('a space over the cap is sampled to exactly the cap', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      final List<int> indices = generator.candidateIndices(
        space: space,
        maxCandidates: 200,
        seed: 7,
      );

      expect(indices, hasLength(200));
      expect(indices.toSet(), hasLength(200));
      expect(indices, everyElement(lessThan(space.enumerableCount)));
    });

    test('sampling with the same seed selects the same candidates', () {
      final CandidateSpace space = generator.prepare(loadDemoFarm());

      final List<int> first = generator.candidateIndices(
        space: space,
        maxCandidates: 150,
        seed: 42,
      );
      final List<int> second = generator.candidateIndices(
        space: space,
        maxCandidates: 150,
        seed: 42,
      );

      expect(first, second);
    });

    test('a pinned allocation is always included in a sampled run', () {
      final Farm farm = loadDemoFarm();
      final CandidateSpace space = generator.prepare(farm);
      final CropAllocation pinned = space.allocationAt(1234);

      final List<int> indices = generator.candidateIndices(
        space: space,
        maxCandidates: 50,
        seed: 3,
        alwaysInclude: pinned,
      );

      expect(indices, contains(1234));
    });
  });
}
