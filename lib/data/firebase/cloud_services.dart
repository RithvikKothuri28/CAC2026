import 'package:cloud_functions/cloud_functions.dart';

import '../../app/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../repositories/data_codec.dart';
import 'firebase_failure.dart';
import 'firebase_privacy_service.dart';

class HarvestPassportService {
  const HarvestPassportService(this._functions, this._config, this._features);
  final FirebaseFunctions _functions;
  final AppConfig _config;
  final FeatureConfig _features;
  static const allowedFields = {
    'crop',
    'field',
    'plantingDate',
    'harvestDate',
    'practices',
    'inputRecords',
    'handlingEvents',
    'storageEvents',
    'notes',
  };

  Future<String> publish({
    required String farmId,
    required String batchId,
    required List<String> fields,
  }) => firebaseGuard(() async {
    if (!_features.harvestPublishingEnabled) {
      throw const ConfigurationFailure(
        'Public Harvest Passport publishing is disabled for this environment.',
      );
    }
    FarmDataCodec.validateId(farmId);
    FarmDataCodec.validateId(batchId);
    if (!fields.contains('crop') ||
        fields.any((field) => !allowedFields.contains(field))) {
      throw const DataValidationFailure(
        'Select the crop and only supported public passport fields.',
      );
    }
    // Check deployment configuration before publishing a URL the user cannot use.
    publicUrl('validation');
    final response = await _functions
        .httpsCallable('publishHarvestPassport')
        .call<Map<String, dynamic>>({
          'farmId': farmId,
          'batchId': batchId,
          'fields': fields.toSet().toList(),
        });
    final id = response.data['passportId'];
    if (id is! String || id.isEmpty) {
      throw const RepositoryUnavailableFailure(
        'The publication service returned an invalid response.',
      );
    }
    return id;
  });

  Future<void> unpublish({
    required String farmId,
    required String passportId,
  }) => firebaseGuard(() async {
    FarmDataCodec.validateId(farmId);
    FarmDataCodec.validateId(passportId);
    await _functions.httpsCallable('deleteHarvestPassport').call<void>({
      'farmId': farmId,
      'passportId': passportId,
    });
  });

  String publicUrl(String id) {
    FarmDataCodec.validateId(id);
    if (_config.publicPassportBaseUrl.isEmpty) {
      throw const ConfigurationFailure(
        'A public Harvest Passport URL has not been configured.',
      );
    }
    final base = _config.publicPassportBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/$id';
  }
}

class CloudExplanationService {
  const CloudExplanationService(this._functions, this._features, this._privacy);
  final FirebaseFunctions _functions;
  final FeatureConfig _features;
  final FirebasePrivacyService _privacy;

  Future<String> explain({
    required String farmId,
    required String question,
    required Map<String, dynamic> context,
  }) async {
    if (!_features.cloudAssistantEnabled ||
        !_privacy.current.cloudAssistantConsent) {
      throw const AiProviderFailure(
        'Cloud explanation is disabled. Use the local calculated explanation.',
      );
    }
    try {
      FarmDataCodec.validateId(farmId);
      if (question.trim().isEmpty || question.length > 2000) {
        throw const DataValidationFailure(
          'Enter a question of 1–2,000 characters.',
        );
      }
      final result = await _functions
          .httpsCallable('explainFarm')
          .call<Map<String, dynamic>>({
            'farmId': farmId,
            'question': question.trim(),
            'context': FarmDataCodec.validatePayload(context),
          });
      final explanation = result.data['explanation'];
      if (explanation is! String || explanation.isEmpty) {
        throw const AiProviderFailure('Cloud explanation returned no text.');
      }
      return explanation;
    } on AiProviderFailure {
      rethrow;
    } on Object catch (error) {
      final failure = firebaseFailure(error);
      throw AiProviderFailure(
        'Cloud explanation is unavailable. Use the local calculated explanation.',
        code: failure.code,
        cause: failure,
      );
    }
  }
}
