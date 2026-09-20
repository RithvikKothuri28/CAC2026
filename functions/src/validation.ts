import { HttpsError } from 'firebase-functions/v2/https';

export type JsonMap = Record<string, unknown>;

export function object(value: unknown, label: string): JsonMap {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpsError('invalid-argument', `${label} must be an object.`);
  }
  return value as JsonMap;
}

export function onlyKeys(value: JsonMap, keys: readonly string[], label: string): void {
  if (Object.keys(value).some((key) => !keys.includes(key))) {
    throw new HttpsError('invalid-argument', `${label} contains unsupported fields.`);
  }
}

export function documentId(value: unknown, label: string): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError('invalid-argument', `${label} is invalid.`);
  }
  return value;
}

export function string(value: unknown, label: string, max: number): string {
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > max) {
    throw new HttpsError('invalid-argument', `${label} must contain 1–${max} characters.`);
  }
  return value.trim();
}

function calendarDate(value: unknown, label: string): string {
  const date = string(value, label, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(date)) || new Date(date).toISOString().slice(0, 10) !== date) {
    throw new HttpsError('invalid-argument', `${label} must be a valid ISO calendar date.`);
  }
  return date;
}

export const passportFields = [
  'crop', 'field', 'plantingDate', 'harvestDate', 'practices',
  'inputRecords', 'handlingEvents', 'storageEvents', 'notes',
] as const;

function stringList(value: unknown, label: string): string[] {
  if (!Array.isArray(value) || value.length > 40) throw new HttpsError('invalid-argument', `${label} must have at most 40 entries.`);
  return value.map((entry) => string(entry, label, 200));
}

function eventList(value: unknown, label: string): JsonMap[] {
  if (!Array.isArray(value) || value.length > 40) throw new HttpsError('invalid-argument', `${label} must have at most 40 entries.`);
  return value.map((entry) => {
    const record = object(entry, label);
    onlyKeys(record, ['name', 'date', 'details'], label);
    const safe: JsonMap = { name: string(record.name, `${label}.name`, 200) };
    if (record.date !== undefined) safe.date = calendarDate(record.date, `${label}.date`);
    if (record.details !== undefined) safe.details = string(record.details, `${label}.details`, 500);
    return safe;
  });
}

/** Copies individually validated selected values; never spreads a private source document. */
export function sanitizePassport(batch: unknown, selection: unknown): JsonMap {
  const source = object(batch, 'Harvest batch');
  if (!Array.isArray(selection) || selection.length === 0 || selection.length > passportFields.length
    || selection.some((key) => !passportFields.includes(key)) || new Set(selection).size !== selection.length) {
    throw new HttpsError('invalid-argument', 'Select unique supported publication fields.');
  }
  if (!selection.includes('crop')) throw new HttpsError('invalid-argument', 'The published crop is required.');
  const result: JsonMap = { schemaVersion: 1, provenance: 'farmerSupplied', selectedFields: [...selection] };
  for (const field of selection as string[]) {
    if (source[field] === undefined) throw new HttpsError('invalid-argument', `Selected field ${field} is missing from this batch.`);
    switch (field) {
      case 'crop': case 'field': result[field] = string(source[field], field, 200); break;
      case 'notes': result[field] = string(source[field], field, 2000); break;
      case 'plantingDate': case 'harvestDate': result[field] = calendarDate(source[field], field); break;
      case 'practices': result[field] = stringList(source[field], field); break;
      case 'inputRecords': case 'handlingEvents': case 'storageEvents': result[field] = eventList(source[field], field); break;
    }
  }
  return result;
}

export const metricNames = [
  'revenue', 'operatingExpense', 'operatingIncome', 'debtService', 'cashAfterDebtService',
  'waterUsage', 'nitrogenUsage', 'acreage', 'cropDiversity', 'practiceSatisfied', 'practiceTotal',
  'candidatesGenerated', 'candidatesPruned', 'candidatesEvaluated', 'feasiblePlans', 'paretoPlans',
  'mean', 'median', 'standardDeviation', 'p05', 'p25', 'p75', 'p95',
  'probabilityNegativeCashFlow', 'probabilityPositiveCashFlow',
] as const;

export function sanitizeExplanationContext(value: unknown): Record<string, number> {
  const source = object(value, 'Calculation context');
  onlyKeys(source, metricNames, 'Calculation context');
  if (Object.keys(source).length === 0) throw new HttpsError('invalid-argument', 'Calculated metrics are required.');
  const clean: Record<string, number> = {};
  for (const [name, metric] of Object.entries(source)) {
    if (typeof metric !== 'number' || !Number.isFinite(metric)) throw new HttpsError('invalid-argument', 'Metrics must be finite numbers.');
    clean[name] = metric;
  }
  return clean;
}

/** Provider may reference metrics but cannot originate numerical values. */
export function renderExplanation(value: unknown, metrics: Record<string, number>): string {
  const narrative = string(value, 'Provider explanation', 6000);
  const template = narrative.replace(/\{\{([A-Za-z][A-Za-z0-9]*)\}\}/g, (_match, key: string) => {
    if (!(key in metrics)) throw new HttpsError('unavailable', 'Provider referenced an unavailable calculation.');
    return 'CALCULATED_VALUE';
  });
  if (/[\p{Number}{}]/u.test(template) || /\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|half|quarter|double|triple)\b/i.test(template)) {
    throw new HttpsError('unavailable', 'Provider introduced an unsupported numerical statement.');
  }
  return narrative.replace(/\{\{([A-Za-z][A-Za-z0-9]*)\}\}/g, (_match, key: string) => String(metrics[key]));
}
