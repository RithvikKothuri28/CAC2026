import 'dart:convert';

import '../../domain/models/farm.dart';

/// Assembles the bundled Congressional App Challenge demo farm.
///
/// Parsing is deliberately kept free of Flutter imports so the demo farm can
/// be loaded in pure-Dart unit tests and, eventually, on a server — the app
/// layer only has to supply the three asset strings.
class DemoDataset {
  const DemoDataset._();

  static const String farmAssetPath = 'assets/demo/demo_farm.json';
  static const String cropProfilesAssetPath = 'assets/demo/crop_profiles.json';
  static const String constraintsAssetPath =
      'assets/demo/demo_constraints.json';

  /// Every asset the demo farm needs, in load order.
  static const List<String> assetPaths = <String>[
    farmAssetPath,
    cropProfilesAssetPath,
    constraintsAssetPath,
  ];

  /// The seed used for demo simulations, so a run shown to a judge on stage
  /// is identical to the one rehearsed the night before.
  static const int deterministicSeed = 20260214;

  /// Builds the demo [Farm] from raw asset contents.
  ///
  /// Crops and constraints live in their own files so a farmer can later swap
  /// crop assumptions without touching field data; this merges them back into
  /// the single farm document the domain models expect.
  static Farm assemble({
    required String farmJson,
    required String cropProfilesJson,
    required String constraintsJson,
  }) {
    final Map<String, dynamic> farmMap =
        jsonDecode(farmJson) as Map<String, dynamic>;

    farmMap['cropProfiles'] = jsonDecode(cropProfilesJson) as List<dynamic>;
    farmMap['constraints'] = jsonDecode(constraintsJson) as List<dynamic>;

    return Farm.fromJson(farmMap);
  }
}
