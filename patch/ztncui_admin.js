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

async function main() {
  const password = readPassword();
  if (!password) {
    throw new Error('empty ztncui credential');
  }

  const hash = await argon2.hash(password, { type: argon2.argon2i });
  const users = {
    admin: {
      name: 'admin',
      pass_set: true,
      hash,
    },
  };

  fs.mkdirSync('/app/ztncui/src/etc', { recursive: true });
  fs.writeFileSync('/app/ztncui/src/etc/passwd', JSON.stringify(users));
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
