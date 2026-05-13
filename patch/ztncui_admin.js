const fs = require('fs');
let argon2;

try {
  argon2 = require('argon2');
} catch (error) {
  argon2 = require('/app/ztncui/src/node_modules/argon2');
}

function readPassword() {
  const passwordFile = process.env.ZTNCUI_ADMIN_PASSWORD_FILE || '';
  if (passwordFile) {
    return fs.readFileSync(passwordFile, 'utf8').replace(/\r?\n$/, '');
  }
  return process.env.ZTNCUI_ADMIN_PASSWORD || '';
}

function readUsers(passwdPath) {
  try {
    const users = JSON.parse(fs.readFileSync(passwdPath, 'utf8'));
    if (!users || typeof users !== 'object' || Array.isArray(users)) {
      throw new Error('invalid ztncui passwd format');
    }
    return users;
  } catch (error) {
    if (error.code === 'ENOENT') {
      return {};
    }
    throw error;
  }
}

async function main() {
  const password = readPassword();
  if (!password) {
    throw new Error('empty ztncui credential');
  }

  const passwdPath = '/app/ztncui/src/etc/passwd';
  const hash = await argon2.hash(password, { type: argon2.argon2i });
  const users = readUsers(passwdPath);
  users.admin = {
    ...(users.admin && typeof users.admin === 'object' ? users.admin : {}),
    name: 'admin',
    pass_set: true,
    hash,
  };

  fs.mkdirSync('/app/ztncui/src/etc', { recursive: true });
  fs.writeFileSync(passwdPath, JSON.stringify(users));
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
