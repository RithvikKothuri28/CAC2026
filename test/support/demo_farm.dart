import 'dart:io';

import 'package:farmtwin/data/demo/demo_dataset.dart';
import 'package:farmtwin/domain/models/farm.dart';

/// Loads the bundled demo farm straight from disk.
///
/// Tests read the asset files rather than going through `rootBundle`, which
/// keeps the domain suite free of any Flutter binding setup. This works
/// because [DemoDataset.assemble] takes strings, not assets.
Farm loadDemoFarm() => DemoDataset.assemble(
  farmJson: File(DemoDataset.farmAssetPath).readAsStringSync(),
  cropProfilesJson: File(DemoDataset.cropProfilesAssetPath).readAsStringSync(),
  constraintsJson: File(DemoDataset.constraintsAssetPath).readAsStringSync(),
);
