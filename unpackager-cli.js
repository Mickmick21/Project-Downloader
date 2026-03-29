#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const JSZip = require('./dependencies/jszip.min.js');
global.JSZip = JSZip;
const unpackage = require('./unpackager');

async function main() {
    const input = process.argv[2];
    const output = process.argv[3] || 'output.sb3';

    if (!input) {
        console.error('Usage: node unpackager-cli.js <input.html> [output.sb3]');
        process.exit(1);
    }

    const data = fs.readFileSync(input);

    try {
        const result = await unpackage(data);

        fs.writeFileSync(output, Buffer.from(result.data));

        console.log(`✓ Unpacked as ${output} (${result.type})`);
    } catch (e) {
        console.error('✗ Failed:', e.message);
        process.exit(1);
    }
}

main();
