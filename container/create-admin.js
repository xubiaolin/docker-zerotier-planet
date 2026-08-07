'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const argon2 = require('/opt/ztncui/src/node_modules/argon2');

async function readStdin() {
  let value = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) value += chunk;
  return value.replace(/[\r\n]+$/, '');
}

async function main() {
  const target = process.argv[2];
  if (!target) throw new Error('passwd target path is required');
  const password = await readStdin();
  if (password.length < 16) throw new Error('administrator password must contain at least 16 characters');

  const users = {
    admin: {
      name: 'admin',
      pass_set: true,
      hash: await argon2.hash(password),
    },
  };
  await fs.mkdir(path.dirname(target), { recursive: true });
  const temporary = `${target}.tmp.${process.pid}`;
  await fs.writeFile(temporary, JSON.stringify(users), { mode: 0o600 });
  await fs.rename(temporary, target);
}

main().catch((error) => {
  process.stderr.write(`failed to create administrator credentials: ${error.message}\n`);
  process.exitCode = 1;
});
