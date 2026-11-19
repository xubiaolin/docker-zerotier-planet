#!/usr/bin/env bash
# Run against an image built from this checkout. All mounted data is disposable.
set -euo pipefail
image=${1:-planet-retry-safe:worktree}
docker run --rm -i --network none -e IP_ADDR4=192.0.2.10 "$image" bash -se <<'TEST'
set -eo pipefail
one=/var/lib/zerotier-one
init() { node /app/initialize.js; }
hashes() {
    find "$one" /app/config /app/dist /app/ztncui -type f ! -name '.planet-init.pending' -print0 |
        sort -z | xargs -0 -r sha256sum
}

# A read-only probe uses existing legacy settings without creating directories.
mkdir /tmp/saved
DEPLOYMENT_DATA=/tmp/saved IP_ADDR4= node /app/settings.js >/tmp/settings
test "$(wc -l </tmp/settings)" = 5
test -z "$(tr -d '\n' </tmp/settings)"
test -z "$(ls -A /tmp/saved)"
mkdir -p /tmp/saved/one /tmp/saved/ztncui/src /tmp/saved/config
printf '%s\n' '{"roots":[{"stableEndpoints":["2001:db8::42/20001"]}]}' >/tmp/saved/one/moon.json
printf '%s\n' 'HTTP_PORT="20002"' 'ZT_ADDR=localhost:1' >/tmp/saved/ztncui/src/.env
DEPLOYMENT_DATA=/tmp/saved IP_ADDR4= FILE_SERVER_PORT=20003 node /app/settings.js >/tmp/settings
printf '%s\n' 20001 20002 20003 '' '2001:db8::42' | cmp /tmp/settings -
node /app/settings.js validate 20001 20002 20003 '' '2001:db8::42'
node /app/settings.js validate 020001 020002 020003 '' '2001:db8::42'
printf '%s\n' '020002' >/tmp/saved/config/ztncui.port
DEPLOYMENT_DATA=/tmp/saved IP_ADDR4= FILE_SERVER_PORT=020003 node /app/settings.js >/tmp/settings
printf '%s\n' 20001 20002 20003 '' '2001:db8::42' | cmp /tmp/settings -
if node /app/settings.js validate 020002 20002 20003 '' '2001:db8::42' 2>/dev/null; then exit 1; fi
if node /app/settings.js validate 20002 20002 20003 '' '2001:db8::42' 2>/dev/null; then exit 1; fi
if node /app/settings.js validate 20001 20002 20003 '' '' 2>/dev/null; then exit 1; fi
if node /app/settings.js validate 20001 20002 20003 'localhost' '' 2>/dev/null; then exit 1; fi
for address in :: 0:0:0:0:0:0:0:0 '2001:db8::42%eth0'; do
    if node /app/settings.js validate 20001 20002 20003 '' "$address" 2>/dev/null; then exit 1; fi
done
if node /app/settings.js validate 20001 20002 20003 0.0.0.0 '' 2>/dev/null; then exit 1; fi
echo 65536 >/tmp/saved/config/ztncui.port
if DEPLOYMENT_DATA=/tmp/saved node /app/settings.js 2>/dev/null; then exit 1; fi

# Interrupt publication across Docker mounts, then replay exactly the same plan.
cat >/tmp/stop.cjs <<'JS'
const fs = require('node:fs');
const rename = fs.renameSync;
fs.renameSync = (src, dest) => {
    if (dest === '/app/dist/planet') process.exit(77);
    rename(src, dest);
};
JS
if NODE_OPTIONS=--require=/tmp/stop.cjs node /app/initialize.js; then exit 1; else test "$?" -eq 77; fi
test -s "$one/.planet-init.pending"
sha256sum "$one/identity.secret" > /tmp/identity.sha256
sha256sum /app/config/.initial-admin-password >/tmp/initial.sha256
init
sha256sum -c --status /tmp/identity.sha256
sha256sum -c --status /tmp/initial.sha256
test ! -e "$one/.planet-init.pending"
test -s /app/dist/planet

# Keep the first password private across interrupted initialization and issue it once.
test "$(stat -c %a /app/config/.initial-admin-password)" = 600
initial=$(node /app/admin-password.js initial)
test "${#initial}" -eq 32
test -z "$(node /app/admin-password.js initial)"
test ! -e /app/config/.initial-admin-password
passwd=/app/ztncui/src/etc/passwd
node - "$passwd" <<'JS'
const fs = require('node:fs');
const passwd = process.argv[2];
const users = JSON.parse(fs.readFileSync(passwd));
users.second = { ...users.admin, name: 'second' };
fs.writeFileSync(passwd, JSON.stringify(users));
JS
reset=$(node /app/admin-password.js reset)
test "${#reset}" -eq 32
test "$reset" != "$initial"
printf '%s\n%s\n' "$initial" "$reset" | node -e '
    const fs = require("node:fs");
    const assert = require("node:assert/strict");
    const argon2 = require("/opt/ztncui/src/node_modules/argon2");
    const [initial, reset] = fs.readFileSync(0, "utf8").trimEnd().split("\n");
    const users = JSON.parse(fs.readFileSync(process.argv[1]));
    (async () => {
        assert.equal(users.second.name, "second");
        assert(await argon2.verify(users.second.hash, initial));
        assert(await argon2.verify(users.admin.hash, reset));
        assert(!(await argon2.verify(users.admin.hash, initial)));
    })().catch(error => { throw error; });
' "$passwd"

node - "$passwd" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { atomicWrite } = require('/app/settings');
const target = process.argv[2];
const before = fs.readFileSync(target);
const files = fs.readdirSync(path.dirname(target)).sort();
fs.renameSync = () => { throw new Error('injected credential write failure'); };
assert.throws(() => atomicWrite(target, '{}'), /injected credential write failure/);
assert.deepEqual(fs.readFileSync(target), before);
assert.deepEqual(fs.readdirSync(path.dirname(target)).sort(), files);
JS

# Update persisted port spellings with no changes to the client artifacts.
sha256sum /app/dist/planet /app/dist/*.moon >/tmp/artifacts.sha256
printf '09994\r\n' >/app/config/zerotier-one.port
printf '003443\n' >/app/config/ztncui.port
init
test "$(cat /app/config/zerotier-one.port)" = 9994
test "$(cat /app/config/ztncui.port)" = 3443
sha256sum -c --status /tmp/artifacts.sha256
hashes >/tmp/complete
IP_ADDR4=192.0.2.20 ZT_PORT=19994 SECRET_KEY=changed init
hashes | cmp /tmp/complete -

# Restore either damaged Planet from the valid copy without regenerating it.
for artifact in "$one/planet" /app/dist/planet; do
    printf 'damaged Planet\n' > "$artifact"
    init
    hashes | cmp /tmp/complete -
done

# External endpoints can differ from listen ports and must match signed files.
printf '192.0.2.20\n' >/app/config/ip_addr4
if init >/tmp/result 2>&1; then exit 1; fi
grep -q '公网地址' /tmp/result
printf '192.0.2.10\n' >/app/config/ip_addr4
if ZT_ADVERTISED_PORT=19994 init >/tmp/result 2>&1; then exit 1; fi
grep -q '公网 ZeroTier 端口' /tmp/result
printf '19995\n' >/app/config/zerotier-one.port
ZT_ADVERTISED_PORT=9994 init
test "$(cat /app/config/zerotier-advertised.port)" = 9994
sha256sum -c --status /tmp/artifacts.sha256
printf '9994\n' >/app/config/zerotier-one.port
init
hashes | cmp /tmp/complete -

# Existing download links may also address ordinary files under a subdirectory.
mkdir -p '/app/dist/user files'
echo '{"available":true}' >'/app/dist/user files/example.json'
ln -s '/app/dist/user files/example.json' /app/dist/example.json
ln -s /app/config /app/dist/private
FILE_SERVER_PORT=23001 node /app/http_server.js &
server=$!
for ((i=0; i<30; i++)); do
    if curl --silent --max-time 1 -o /dev/null http://127.0.0.1:23001/; then break; fi
    sleep .1
done
key=$(cat /app/config/file_server.key)
curl -fsSG --data-urlencode "key=$key" 'http://127.0.0.1:23001/user%20files/example.json' | cmp '/app/dist/user files/example.json' -
curl -fsSIG --data-urlencode "key=$key" http://127.0.0.1:23001/example.json | grep -iq '^Content-Type: application/json'
test "$(curl -sG -o /dev/null -w '%{http_code}' --data-urlencode "key=$key" http://127.0.0.1:23001/private/file_server.key)" = 404
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:23001/example.json)" = 401
kill "$server"
wait "$server" || true
rm -r '/app/dist/user files' /app/dist/example.json /app/dist/private

# Recover each derived file, including the original private Planet from signing
# material after an old image left its unrelated public Planet in the home.
rm "$one/identity.public" "$one/authtoken.secret" /app/dist/*.moon
init
hashes | cmp /tmp/complete -
rm "$one/planet" /app/dist/planet
init
hashes | cmp /tmp/complete -
rm "$one/current.c25519"
init
hashes | cmp /tmp/complete -

# The published Planet binds this installation to its world signing keys.
# A legitimate rotation may be staged before publishing its next Planet.
mkdir /tmp/other-keys
(cd /tmp/other-keys && mkworld --new-keys)
cp "$one/current.c25519" /tmp/original-current
cp /tmp/other-keys/current.c25519 "$one/current.c25519"
init
cp "$one/previous.c25519" /tmp/original-previous
cp /tmp/other-keys/previous.c25519 "$one/previous.c25519"
hashes > /tmp/mixed
if init >/tmp/result 2>&1; then exit 1; fi
grep -q 'verify-keys' /tmp/result
hashes | cmp /tmp/mixed -
cp /tmp/original-previous "$one/previous.c25519"
cp /tmp/original-current "$one/current.c25519"
init
hashes | cmp /tmp/complete -

# genmoon can accept mismatched public and private signing keys. Reject both a
# damaged Moon credential and a .moon signed for this root by another key.
mkdir /tmp/other-moon
cp "$one/moon.json" /tmp/original-moon-json
(cd /tmp/other-moon && zerotier-idtool initmoon "$one/identity.public" >moon.json &&
    node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync("moon.json")); m.roots = JSON.parse(fs.readFileSync("/tmp/original-moon-json")).roots; fs.writeFileSync("moon.json", JSON.stringify(m))' &&
    zerotier-idtool genmoon moon.json >/dev/null)
node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync("/tmp/original-moon-json")); m.signingKey_SECRET = JSON.parse(fs.readFileSync("/tmp/other-moon/moon.json")).signingKey_SECRET; fs.writeFileSync("/var/lib/zerotier-one/moon.json", JSON.stringify(m))'
hashes >/tmp/mixed
if init >/tmp/result 2>&1; then exit 1; fi
hashes | cmp /tmp/mixed -
cp /tmp/original-moon-json "$one/moon.json"
moonfile=$(basename /app/dist/*.moon)
cp "/tmp/other-moon/$moonfile" "/app/dist/$moonfile"
hashes >/tmp/mixed
if init >/tmp/result 2>&1; then exit 1; fi
hashes | cmp /tmp/mixed -
cp "$one/moons.d/$moonfile" "/app/dist/$moonfile"
init
hashes | cmp /tmp/complete -

# Unrecoverable loss must not even recreate a missing derived public identity.
for file in "$one/identity.secret" "$one/moon.json" /app/config/file_server.key /app/ztncui/src/etc/passwd; do
    mv "$file" /tmp/critical-backup
    mv "$one/identity.public" /tmp/public-backup
    hashes > /tmp/before
    if init > /tmp/result 2>&1; then exit 1; fi
    grep -q '还原' /tmp/result
    hashes | cmp /tmp/before -
    mv /tmp/critical-backup "$file"
    mv /tmp/public-backup "$one/identity.public"
done

# Replay an interrupted legacy initmoon which had not yet set stableEndpoints.
cp "$one/identity.secret" /tmp/original-id
cp "$one/moon.json" /tmp/original-moon
find "$one" /app/config /app/dist /app/ztncui -mindepth 1 -delete
cp /tmp/original-id "$one/identity.secret"
node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync("/tmp/original-moon")); m.roots[0].stableEndpoints = []; fs.writeFileSync("/var/lib/zerotier-one/moon.json", JSON.stringify(m))'
init
node -e 'const fs = require("fs"); const a = JSON.parse(fs.readFileSync("/tmp/original-moon")); const b = JSON.parse(fs.readFileSync("/var/lib/zerotier-one/moon.json")); if (a.signingKey_SECRET !== b.signingKey_SECRET || !b.roots[0].stableEndpoints.length) process.exit(1)'
cmp /tmp/original-id "$one/identity.secret"
# An old builder populated public and private identity, a stock Planet and
# mkworld before its entrypoint generated the real instance's identity.
find "$one" /app/config /app/dist /app/ztncui -mindepth 1 -delete
cp /tmp/original-id "$one/identity.secret"
mkdir -p /tmp/stock
(cd /tmp/stock && /usr/sbin/zerotier-idtool generate identity.secret identity.public >/dev/null &&
    /usr/sbin/zerotier-idtool initmoon identity.public >moon.json &&
    node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync("moon.json")); m.roots[0].stableEndpoints = ["192.0.2.123/9994"]; fs.writeFileSync("moon.json", JSON.stringify(m))' &&
    mkworld --new-keys && mkworld)
cp /tmp/stock/world.bin "$one/planet"
touch "$one/mkworld"
hashes >/tmp/copied-builder
if init > /tmp/result 2>&1; then exit 1; fi
grep -q '私钥来源' /tmp/result
hashes | cmp /tmp/copied-builder -

echo '容器初始化、中断重试、派生文件修复和关键材料丢失保护通过'
TEST
