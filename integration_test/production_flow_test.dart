import 'package:cloud_firestore/cloud_firestore.dart' hide Field;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/core/errors/app_failure.dart';
import 'package:farmtwin/data/firebase/firebase_bootstrap.dart';
import 'package:farmtwin/data/firebase/firestore_farm_repository.dart';
import 'package:farmtwin/data/firebase/user_settings.dart';
import 'package:farmtwin/data/repositories/farm_repository.dart';
import 'package:farmtwin/domain/farm_domain.dart';

/// These inputs are isolated test fixtures, never production defaults.
Farm _unseenFarm(String id) {
  final provenance = Provenance(
    source: DataSourceType.userEntered,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
  CropProfile crop(
    String id,
    double yield,
    double price,
    double seed,
    double water,
  ) => CropProfile(
    id: id,
    name: 'Integration crop $id',
    yieldPerAcre: yield,
    pricePerUnit: price,
    yieldUnit: 'unit',
    seedCostPerAcre: seed,
    fertilizerCostPerAcre: 6,
    chemicalCostPerAcre: 1,
    waterCostPerAcre: 2,
    laborCostPerAcre: 3,
    fuelCostPerAcre: 2,
    equipmentCostPerAcre: 1,
    waterPerAcre: water,
    nitrogenPerAcre: 1,
    yieldVolatility: 0,
    priceVolatility: 0,
    rotationFamily: id,
    minimumRotationYears: 0,
    requiresIrrigation: false,
    inputs: const [],
    providesSoilCover: true,
    provenance: provenance,
  );
  return Farm(
    id: id,
    name: 'Unseen integration farm',
    crops: [
      crop('alpha', 20, 10, 5, 2),
      crop('beta', 30, 8, 10, 3),
      // More profitable, but excluded by the field's explicit compatibility.
      crop('excluded', 1000, 100, 1, 0),
    ],
    fields: [
      Field(
        id: 'field-one',
        name: 'User entered field',
        acres: 10,
        currentCropId: 'alpha',
        compatibleCropIds: const ['alpha', 'beta'],
        provenance: provenance,
      ),
    ],
    expenses: [
      Expense(
        id: 'rent',
        name: 'User entered rent',
        annualAmount: 100,
        inflationRate: 0,
        provenance: provenance,
      ),
    ],
    debts: [
      Debt(
        id: 'loan',
        name: 'User entered loan',
        balance: 1000,
        annualInterestRate: 0,
        annualPayment: 100,
        provenance: provenance,
      ),
    ],
    constraints: [
      FarmConstraint(
        id: 'water',
        name: 'Water budget',
        kind: ConstraintKind.maxWater,
        mode: ConstraintMode.hard,
        limit: 30,
      ),
    ],
    settings: FarmSettings(
      currencyCode: 'USD',
      optimization: OptimizationConfig(
        weights: const {Objective.profit: 1},
        exhaustiveLimit: 100,
        candidateLimit: 100,
        frontierLimit: 100,
        seed: 13,
      ),
      simulation: SimulationConfig(
        iterations: 100,
        seed: 17,
        weatherCorrelation: 0,
        marketCorrelation: 0,
        fertilizerVolatility: 0,
        fuelVolatility: 0,
        waterVolatility: 0,
        equipmentFailureProbability: 0,
        equipmentFailureCost: 0,
      ),
      priceGrowthRate: 0,
      expenseInflationRate: 0,
      liquidityReserve: 0,
      alertUtilizationThreshold: .9,
    ),
    provenance: provenance,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'new account, arbitrary farm, engines, persisted reopen, offline edits, passports and deletion',
    (tester) async {
      final config = AppConfig.fromEnvironment();
      // This guard executes before Firebase initialization or any database write.
      expect(config.environment, AppEnvironment.development);
      expect(config.useEmulators, isTrue);
      expect(config.firebaseOptions?.projectId, 'demo-farmtwin');
      expect([
        '127.0.0.1',
        'localhost',
        '10.0.2.2',
      ], contains(config.emulatorHost));
      final services = await FirebaseBootstrap.initialize(config);
      expect(services, isNotNull);
      final cloud = services;
      final firestore = FirebaseFirestore.instance;
      final functions = FirebaseFunctions.instanceFor(
        region: config.functionsRegion,
      );
      final auth = FirebaseAuth.instance;
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'flow-$suffix@example.test';
      const password = 'Integration-fixture-password42';
      final full = _unseenFarm('flow-$suffix');
      var farm = full.copyWith(
        fields: [],
        crops: [],
        expenses: [],
        debts: [],
        constraints: [],
      );
      FirestoreFarmRepository repository = cloud.farms;
      var accountDeleted = false;
      String? passportId;
      try {
        await cloud.auth.signUp(email, password);
        final uid = auth.currentUser!.uid;
        expect(
          await repository.watchFarms().firstWhere((farms) => farms.isEmpty),
          isEmpty,
        );
        await repository.saveFarm(farm);
        await firestore.waitForPendingWrites();
        expect((await repository.readFarm(farm.id)).fields, isEmpty);

        // Persist each normal entry stage through the actual production repository.
        farm = farm.copyWith(crops: full.crops);
        await repository.saveFarm(farm);
        farm = farm.copyWith(fields: full.fields);
        await repository.saveFarm(farm);
        farm = farm.copyWith(expenses: full.expenses);
        await repository.saveFarm(farm);
        farm = farm.copyWith(debts: full.debts);
        await repository.saveFarm(farm);
        farm = farm.copyWith(constraints: full.constraints);
        await repository.saveFarm(farm);
        await firestore.waitForPendingWrites();
        farm = await repository.readFarm(farm.id);
        farm.validate(requireReady: true);
        expect(farm.fields.single.currentCropId, 'alpha');
        expect(farm.fields.single.compatibleCropIds, ['alpha', 'beta']);
        await expectLater(
          repository.saveFarm(
            farm.copyWith(
              fields: [farm.fields.single.copyWith(currentCropId: 'excluded')],
            ),
          ),
          throwsA(
            isA<DataValidationFailure>().having(
              (failure) => failure.message,
              'message',
              contains('must be selected in its compatible crops'),
            ),
          ),
        );
        final accepted = await repository.readFarm(farm.id);
        expect(accepted.fields.single.currentCropId, 'alpha');
        expect(accepted.fields.single.compatibleCropIds, ['alpha', 'beta']);

        final financial = const FinancialEngine().evaluate(
          farm,
          farm.currentPlan,
        );
        // Independently: 10 acres * 20 units * $10; 10 * $20 costs + $100 rent.
        expect(financial.revenue, 2000);
        expect(financial.operatingIncome, 1700);
        expect(financial.cashAfterDebt, 1600);
        final optimization = const OptimizationEngine().run(farm);
        expect(optimization.recommended!.plan.assignments['field-one'], 'beta');
        expect(optimization.recommended!.financial.operatingIncome, 2050);
        expect(optimization.diagnostics.candidatesGenerated, 2);
        for (final plan in [
          optimization.current,
          ...optimization.pareto,
          ...optimization.representatives.values,
        ]) {
          expect(
            plan.plan.assignments.values,
            everyElement(isIn(['alpha', 'beta'])),
          );
        }
        final risk = const MonteCarloEngine().run(
          farm,
          optimization.recommended!.plan,
        );
        expect(risk.mean, 1950);
        expect(risk.standardDeviation, 0);
        await repository.saveEntity(
          farm.id,
          EntityKind.optimizationRuns,
          StoredEntity(id: 'optimized', data: optimization.toJson()),
        );
        await repository.saveEntity(
          farm.id,
          EntityKind.simulationRuns,
          StoredEntity(id: 'risk', data: risk.toJson()),
        );
        final scenario = StressScenario(
          id: 'market-change',
          name: 'User configured market change',
          priceMultiplier: .7,
        );
        await repository.saveEntity(
          farm.id,
          EntityKind.scenarios,
          StoredEntity(id: scenario.id, data: scenario.toJson()),
        );
        final scenarioFarm = const ScenarioEngine().apply(farm, scenario);
        final scenarioRun = const OptimizationEngine().run(scenarioFarm);
        expect(scenarioRun.recommended!.financial.operatingIncome, 1330);
        farm = farm.copyWith(
          constraints: [farm.constraints.single.copyWith(limit: 22)],
          scenarios: [scenario],
        );
        final constrained = const OptimizationEngine().run(farm);
        expect(constrained.recommended!.plan.assignments['field-one'], 'alpha');
        expect(constrained.recommended!.financial.waterUsage, 20);
        await repository.saveFarm(farm);
        await cloud.settings.save(
          const UserSettings(cloudAssistantConsent: true),
        );
        await firestore.waitForPendingWrites();
        final explanation = const LocalExplanationEngine().explain(
          'Explain cash',
          farm,
        );
        expect(explanation, contains('1600.00'));

        // Browser cache is memory-based; native caches also support disk persistence.
        await firestore.disableNetwork();
        farm = farm.copyWith(name: 'Edited offline by real repository');
        await expectLater(
          repository.saveFarm(farm),
          throwsA(isA<NetworkFailure>()),
        );
        final cached = await firestore
            .collection('farms')
            .doc(farm.id)
            .get(const GetOptions(source: Source.cache));
        expect(cached.metadata.isFromCache, isTrue);
        expect(cached.data()!['name'], farm.name);
        expect(repository.currentSyncStatus.hasPendingWrites, isTrue);
        await firestore.enableNetwork();
        await firestore.waitForPendingWrites();
        expect(repository.currentSyncStatus.failure, isNull);

        await repository.close();
        await cloud.auth.signOut();
        expect(auth.currentUser, isNull);
        await cloud.auth.signIn(email, password);
        expect(auth.currentUser!.uid, uid);
        repository = FirestoreFarmRepository(firestore, auth, functions);
        final reopened = await repository.readFarm(farm.id);
        expect(reopened.toJson(), farm.toJson());
        expect((await cloud.settings.read()).cloudAssistantConsent, isTrue);
        final savedOptimization = await repository
            .watchEntities(farm.id, EntityKind.optimizationRuns)
            .firstWhere((entities) => entities.isNotEmpty);
        expect(
          savedOptimization
              .single
              .data['recommended']['financial']['operatingIncome'],
          2050,
        );
        final savedRisk = await repository
            .watchEntities(farm.id, EntityKind.simulationRuns)
            .firstWhere((entities) => entities.isNotEmpty);
        expect(savedRisk.single.data['mean'], 1950);
        final savedScenarios = await repository
            .watchEntities(farm.id, EntityKind.scenarios)
            .firstWhere((entities) => entities.isNotEmpty);
        expect(savedScenarios.single.data['priceMultiplier'], .7);
        final server = await firestore
            .collection('farms')
            .doc(farm.id)
            .get(const GetOptions(source: Source.server));
        expect(server.data()!['ownerId'], uid);
        expect(server.data()!['source'], 'userEntered');
        final serverData = server.data()!['data'] as Map<String, dynamic>;
        final serverField =
            (serverData['fields'] as List).single as Map<String, dynamic>;
        expect(serverField['currentCropId'], 'alpha');
        expect(serverField['compatibleCropIds'], ['alpha', 'beta']);

        await repository.saveEntity(
          farm.id,
          EntityKind.harvestBatches,
          const StoredEntity(
            id: 'batch',
            data: {
              'crop': 'Integration crop alpha',
              'field': 'User entered field',
              'notes': 'Private test note',
            },
          ),
        );
        await firestore.waitForPendingWrites();
        passportId = await cloud.passports.publish(
          farmId: farm.id,
          batchId: 'batch',
          fields: ['crop'],
        );
        final repeated = await cloud.passports.publish(
          farmId: farm.id,
          batchId: 'batch',
          fields: ['crop'],
        );
        expect(repeated, passportId);
        final public = await firestore
            .collection('publicHarvestPassports')
            .doc(passportId)
            .get(const GetOptions(source: Source.server));
        expect(public.data()!['crop'], 'Integration crop alpha');
        expect(public.data()!.containsKey('notes'), isFalse);
        expect(public.data()!.containsKey('ownerId'), isFalse);
        expect(public.data()!.containsKey('farmId'), isFalse);
        await cloud.passports.unpublish(
          farmId: farm.id,
          passportId: passportId,
        );
        expect(
          (await firestore
                  .collection('publicHarvestPassports')
                  .doc(passportId)
                  .get(const GetOptions(source: Source.server)))
              .exists,
          isFalse,
        );
        await repository.deleteEntity(
          farm.id,
          EntityKind.scenarios,
          scenario.id,
        );
        await repository.deleteEntity(
          farm.id,
          EntityKind.harvestBatches,
          'batch',
        );
        await firestore.waitForPendingWrites();
        await repository.deleteFarm(farm.id);
        expect(
          (await firestore
                  .collection('farms')
                  .doc(farm.id)
                  .get(const GetOptions(source: Source.server)))
              .exists,
          isFalse,
        );
        await cloud.auth.reauthenticate(email, password);
        await cloud.auth.deleteAccount();
        accountDeleted = true;
        expect(auth.currentUser, isNull);
      } finally {
        await firestore.enableNetwork();
        if (!accountDeleted && auth.currentUser != null) {
          await cloud.auth.reauthenticate(email, password);
          await cloud.auth.deleteAccount();
        }
        await repository.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
