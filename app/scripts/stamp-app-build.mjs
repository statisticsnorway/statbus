// Only image publication supplies a checkout-proven COMMIT. Local builds are unknown.
import { writeFileSync } from 'node:fs';
const commit = process.argv[2] === '--image' ? process.argv[3] : null;
const commit_sha = /^[0-9a-f]{40}$/.test(commit ?? '') ? commit : null;
writeFileSync('public/_statbus-build.json', JSON.stringify({ commit_sha }) + '\n');
