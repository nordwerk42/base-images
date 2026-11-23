const assert = require('assert');
const os = require('os');
const crypto = require('crypto');

console.log(`Node.js ${process.version}`);
console.log(`Platform: ${os.arch()}`);

// JSON roundtrip
const data = { status: 'ok', values: [1, 2, 3] };
assert.deepStrictEqual(JSON.parse(JSON.stringify(data)), data, 'json roundtrip failed');

// Basic arithmetic
const sum = Array.from({ length: 100 }, (_, i) => i + 1).reduce((a, b) => a + b, 0);
assert.strictEqual(sum, 5050, 'arithmetic failed');

// crypto module
const digest = crypto.createHash('sha256').update('test').digest('hex');
assert.strictEqual(digest.length, 64, 'crypto failed');

// v8 module is available (key debug tool)
const v8 = require('v8');
assert(typeof v8.getHeapStatistics === 'function', 'v8 not available');

// inspector module is available (used for debugging)
const inspector = require('inspector');
assert(typeof inspector.open === 'function', 'inspector not available');

console.log('All tests passed.');
