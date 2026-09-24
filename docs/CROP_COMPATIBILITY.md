# Crop compatibility and record repair

A current crop assignment uses `CropProfile.id`, never its display name. `Field.compatibleCropIds` is the canonical compatibility list. A crop is eligible only when its ID is explicitly selected and its irrigation requirements are met by the field. `Field.isCompatibleWith` is shared by current-plan validation, optimizer candidates, multi-year candidates, and the field selector.

## Confirmed production defect

Read-only inspection of the actual `farmtwin-f64bd` records found two affected fields: each current reference was a valid crop UUID, the same UUID appeared in its compatibility list, the crop required irrigation, and the field was rainfed. The old field form preselected the first crop and every compatible ID while defaulting irrigation to false. `Farm.validate()` verified references but omitted the current assignment's compatibility check. Financial rendering later called `validatePlan()`, which threw `Crop Corn is incompatible with Field 1.` during widget build.

The fix preserves those real agricultural inputs for correction. It never changes irrigation or widens compatibility automatically.

## Forms and validation

- New fields start with no selected compatible IDs and no current assignment.
- Crop profiles keep stable UUIDs through renaming and persistence. Opening the field editor includes newly saved profiles.
- Selecting compatible crops does not select a current crop. The current-crop menu contains only eligible profiles plus `No current crop`.
- Removing compatibility or turning irrigation off preserves the old assignment visibly as invalid. Saving requires an explicit compatible replacement or `No current crop`.
- A field with no current crop is an incomplete input record. It may be saved and reloaded, but optimization and financial calculations remain unavailable until setup is valid.
- Field/crop edits validate the complete farm and await Firestore acceptance. Errors stay in the form.

For an existing affected field, open **My farm > Fields > Edit Field 1**. If the field actually has irrigation, enable **Irrigated**. Otherwise choose a compatible rainfed crop, correct an inaccurate crop-profile irrigation requirement, or explicitly choose **No current crop** while completing setup. The app cannot infer these farm facts.

## Legacy normalization

`FarmDataCodec.migrate` normalizes legacy crop references in the current assignment, compatibility list, and history. Exact stable IDs take precedence over names. An exact, trimmed display name converts only when it identifies one crop profile. Unknown or ambiguous names produce an actionable validation error. `allowedCropIds` is accepted as a legacy alias; conflicting alias/canonical lists are rejected. Missing compatibility becomes an empty list and never implies every crop is allowed.

Read normalization does not write to Firestore. The next explicit successful save persists canonical IDs and `compatibleCropIds`.

`decodeFarm`, `encodeFarm`, and domain engines remain strict. The repository's workspace listener uses `decodeFarmForEditing` to expose existing invalid current assignments solely for correction. That path validates the remaining model and crop references, preserves the original assignment, and does not mark the farm ready. It performs no migration write. Saving and calculation still require strict validation.

The workspace checks readiness before evaluating finances, displays the specific setup problem, and the field canvas handles unassigned crops without dereferencing an empty ID.
