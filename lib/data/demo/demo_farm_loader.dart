import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/farm.dart';
import 'demo_dataset.dart';

/// Loads the demo farm from the app bundle.
///
/// The dataset ships inside the binary, which is what lets Demo Mode run with
/// no Firebase, no account and no network — the offline path the product
/// depends on, and the one the competition demo runs on.
class DemoFarmLoader {
  const DemoFarmLoader();

  Future<Farm> load() async {
    final String farmJson = await rootBundle.loadString(
      DemoDataset.farmAssetPath,
    );
    final String cropProfilesJson = await rootBundle.loadString(
      DemoDataset.cropProfilesAssetPath,
    );
    final String constraintsJson = await rootBundle.loadString(
      DemoDataset.constraintsAssetPath,
    );

    return DemoDataset.assemble(
      farmJson: farmJson,
      cropProfilesJson: cropProfilesJson,
      constraintsJson: constraintsJson,
    );
  }
}
