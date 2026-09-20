import { JsonMap, passportFields } from './validation';

function escape(value: unknown): string {
  return String(value).replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]!);
}

function display(value: unknown): string {
  if (Array.isArray(value)) return `<ul>${value.map((entry) => `<li>${display(entry)}</li>`).join('')}</ul>`;
  if (value !== null && typeof value === 'object') {
    const entry = value as JsonMap;
    return ['name', 'date', 'details'].filter((key) => entry[key] !== undefined).map((key) => escape(entry[key])).join(' · ');
  }
  return escape(value);
}

/** Public rendering uses the same explicit field allowlist and escapes all farmer input. */
export function renderPassportPage(passport: JsonMap): string {
  const labels: Record<string, string> = { crop: 'Crop', field: 'Field', plantingDate: 'Planting date', harvestDate: 'Harvest date', practices: 'Practices', inputRecords: 'Selected inputs', handlingEvents: 'Handling', storageEvents: 'Storage', notes: 'Farmer notes' };
  const fields = passportFields.filter((key) => passport[key] !== undefined)
    .map((key) => `<dt>${labels[key]}</dt><dd>${display(passport[key])}</dd>`).join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Harvest Passport · FarmTwin</title><style>body{font:17px/1.6 system-ui,sans-serif;background:#f5f6ef;color:#203e2e;margin:0;padding:32px 20px}main{max-width:700px;margin:auto}h1{font-size:36px;line-height:1.2}header{border-bottom:1px solid #c9d6c4;padding-bottom:24px}small{color:#49634d}dl{display:grid;grid-template-columns:minmax(110px,1fr) 3fr;gap:18px}dt{font-weight:700}dd{margin:0;overflow-wrap:anywhere;white-space:pre-wrap}ul{padding-left:20px;margin:0}footer{border-top:1px solid #c9d6c4;margin-top:30px;padding-top:20px}</style></head><body><main><header><small>FARMTWIN</small><h1>Harvest Passport</h1><p>Information selected and published by the farmer.</p></header><dl>${fields}</dl><footer><small>Farmer supplied. These records have not been independently verified. A passport describes reported practices and does not certify food quality, health benefits, or sustainability.</small></footer></main></body></html>`;
}
