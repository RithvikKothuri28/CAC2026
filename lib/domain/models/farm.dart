import '../../core/utilities/json_utils.dart';
import 'crop_allocation.dart';
import 'crop_profile.dart';
import 'debt.dart';
import 'farm_constraint.dart';
import 'farm_field.dart';
import 'fixed_expense.dart';

/// The farm's digital twin: every input the deterministic engines need.
///
/// A [Farm] is immutable. Scenario analysis produces a modified copy rather
/// than mutating the twin, so the baseline is always recoverable.
class Farm {
  Farm({
    required this.id,
    required this.name,
    required this.planYear,
    required List<FarmField> fields,
    required List<CropProfile> cropProfiles,
    List<FixedExpense> fixedExpenses = const <FixedExpense>[],
    List<Debt> debts = const <Debt>[],
    List<FarmConstraint> constraints = const <FarmConstraint>[],
    this.location = '',
  }) : fields = List<FarmField>.unmodifiable(
         fields.toList()
           ..sort((FarmField a, FarmField b) => a.id.compareTo(b.id)),
       ),
       cropProfiles = List<CropProfile>.unmodifiable(
         cropProfiles.toList()
           ..sort((CropProfile a, CropProfile b) => a.id.compareTo(b.id)),
       ),
       fixedExpenses = List<FixedExpense>.unmodifiable(fixedExpenses),
       debts = List<Debt>.unmodifiable(debts),
       constraints = List<FarmConstraint>.unmodifiable(constraints),
       _fieldsById = <String, FarmField>{
         for (final FarmField f in fields) f.id: f,
       },
       _cropsById = <String, CropProfile>{
         for (final CropProfile c in cropProfiles) c.id: c,
       };

  final String id;
  final String name;
  final String location;

  /// The season being planned. History entries are compared against this.
  final int planYear;

  /// Fields, always sorted by id for deterministic enumeration.
  final List<FarmField> fields;

  /// Crop options available to this farm, always sorted by id.
  final List<CropProfile> cropProfiles;

  final List<FixedExpense> fixedExpenses;
  final List<Debt> debts;
  final List<FarmConstraint> constraints;

  final Map<String, FarmField> _fieldsById;
  final Map<String, CropProfile> _cropsById;

  FarmField? field(String id) => _fieldsById[id];
  CropProfile? crop(String id) => _cropsById[id];

  double get totalAcres =>
      fields.fold<double>(0, (double sum, FarmField f) => sum + f.acres);

  double get irrigatedAcres => fields
      .where((FarmField f) => f.irrigated)
      .fold<double>(0, (double sum, FarmField f) => sum + f.acres);

  /// Fixed operating expense for the plan year.
  double get totalFixedExpense => fixedExpenses.fold<double>(
    0,
    (double sum, FixedExpense e) => sum + e.annualAmount,
  );

  /// Scheduled debt payments for the plan year.
  double get totalDebtService =>
      debts.fold<double>(0, (double sum, Debt d) => sum + d.annualPayment);

  double get totalDebtPrincipal =>
      debts.fold<double>(0, (double sum, Debt d) => sum + d.principal);

  /// Constraints the engines should evaluate, in stable order.
  List<FarmConstraint> get activeConstraints => constraints
      .where((FarmConstraint c) => c.isActive)
      .toList(growable: false);

  List<FarmConstraint> get hardConstraints =>
      constraints.where((FarmConstraint c) => c.isHard).toList(growable: false);

  List<FarmConstraint> get preferenceConstraints => constraints
      .where((FarmConstraint c) => c.isPreference)
      .toList(growable: false);

  /// The plan the farm is operating today, drawn from each field's current
  /// crop. Fields with no assignment are omitted.
  CropAllocation get currentAllocation => CropAllocation(<String, String>{
    for (final FarmField f in fields)
      if (f.currentCropId != null) f.id: f.currentCropId!,
  });

  /// Whether every field has a current crop, i.e. the baseline plan is
  /// complete enough to compare against optimised plans.
  bool get hasCompleteCurrentAllocation =>
      fields.every((FarmField f) => f.currentCropId != null);

  Farm copyWith({
    int? planYear,
    List<FarmField>? fields,
    List<CropProfile>? cropProfiles,
    List<FixedExpense>? fixedExpenses,
    List<Debt>? debts,
    List<FarmConstraint>? constraints,
  }) => Farm(
    id: id,
    name: name,
    location: location,
    planYear: planYear ?? this.planYear,
    fields: fields ?? this.fields,
    cropProfiles: cropProfiles ?? this.cropProfiles,
    fixedExpenses: fixedExpenses ?? this.fixedExpenses,
    debts: debts ?? this.debts,
    constraints: constraints ?? this.constraints,
  );

  factory Farm.fromJson(Map<String, dynamic> json) => Farm(
    id: asString(json['id']),
    name: asString(json['name']),
    location: asString(json['location']),
    planYear: asInt(json['planYear'], fallback: DateTime.now().year),
    fields: asObjectList(json['fields'], FarmField.fromJson),
    cropProfiles: asObjectList(json['cropProfiles'], CropProfile.fromJson),
    fixedExpenses: asObjectList(json['fixedExpenses'], FixedExpense.fromJson),
    debts: asObjectList(json['debts'], Debt.fromJson),
    constraints: asObjectList(json['constraints'], FarmConstraint.fromJson),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'location': location,
    'planYear': planYear,
    'fields': fields.map((FarmField f) => f.toJson()).toList(),
    'cropProfiles': cropProfiles.map((CropProfile c) => c.toJson()).toList(),
    'fixedExpenses': fixedExpenses.map((FixedExpense e) => e.toJson()).toList(),
    'debts': debts.map((Debt d) => d.toJson()).toList(),
    'constraints': constraints.map((FarmConstraint c) => c.toJson()).toList(),
  };

  @override
  String toString() =>
      'Farm($id, ${fields.length} fields, ${totalAcres.toStringAsFixed(0)}ac)';
}
