const fs = require('fs');
const path = require('path');
let argon2;

try {
  argon2 = require('argon2');
} catch (error) {
  argon2 = require('/app/ztncui/src/node_modules/argon2');
}

function readPassword() {
  const passwordFile = process.env.ZTNCUI_ADMIN_PASSWORD_FILE || process.env.ZTNCUI_RESET_PASSWORD_FILE || '';
  if (passwordFile) {
    return fs.readFileSync(passwordFile, 'utf8').replace(/\r?\n$/, '');
  }
  return process.env.ZTNCUI_ADMIN_PASSWORD || '';
}

async function main() {
  const password = readPassword();
  if (!password) {
    throw new Error('empty ztncui credential');
  }

  const passwdPath = process.env.ZTNCUI_PASSWD_PATH || '/app/ztncui/src/etc/passwd';
  const hash = await argon2.hash(password, { type: argon2.argon2i });
  const users = {
    admin: {
      name: 'admin',
      pass_set: true,
      hash,
    },
  };

  fs.mkdirSync(path.dirname(passwdPath), { recursive: true });
  fs.writeFileSync(passwdPath, JSON.stringify(users));
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
