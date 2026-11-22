// z2qt08: screenshots of Erik's map prototypes (www.statbus.org/charts), the ones the owner's
// notes link, so the task shows what they look like. Both prototypes load MapTiler with a key
// that now answers 403, so live they show a blank map. The copies served from
// tmp/hug/z2qt08-prototypes (127.0.0.1:8765) swap only the style URL for OpenFreeMap's,
// keeping Erik's code and data; the cluster labels get text-font Noto Sans Regular, the only font family OpenFreeMap serves (his default font 404s and stops the layers). Headed Firefox with WebGL forced on:
// headless Firefox reports 'WebGL is currently disabled' and MapLibre draws no layers.
import { firefox } from '/Users/jhf/.brovs/ui-evidence/node_modules/playwright-core/index.mjs';
const out = 'tmp/hug';
const b = await firefox.launch({ headless: false, firefoxUserPrefs: { 'webgl.force-enabled': true, 'webgl.disabled': false } });
const page = await (await b.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
page.on('pageerror', e => console.error('pageerror', String(e).slice(0, 200)));
const shots = [];
const snap = async (name, note) => { const path = `${out}/z2qt08-${name}.png`; await page.screenshot({ path }); shots.push({ path, note }); };

await page.goto('https://www.statbus.org/charts/statistical_units.html?ver=233');
await page.waitForTimeout(6000);
await snap('proto-live-blank', 'live www.statbus.org/charts/statistical_units.html today: MapTiler key refused (403), map blank');

await page.goto('http://127.0.0.1:8765/statistical_units.local.html');
await page.waitForTimeout(10000);
await page.fill('#search', '');
await page.waitForTimeout(5000);
await snap('proto-country', 'Erik\'s statistical_units prototype on OpenFreeMap tiles: Norway, establishments, clusters by count (artificial data)');

await page.check('input.type-filter[value="enterprise"]');
await page.check('input.type-filter[value="legal_unit"]');
await page.waitForTimeout(5000);
await snap('proto-all-types', 'all three unit types: clusters turn grey when types mix; legend totals per type and variable');

await page.mouse.move(870, 600);
for (let i = 0; i < 8; i++) { await page.mouse.wheel(0, -400); await page.waitForTimeout(500); }
await page.waitForTimeout(4000);
await snap('proto-zoomed', 'zoomed towards Oslo: clusters split, single units coloured by type, darker by employees');

await page.mouse.click(700, 450);
await page.waitForTimeout(1500);
await snap('proto-popup', 'click on a unit or cluster: popup or zoom');
console.log(JSON.stringify(shots, null, 1));
await b.close();
