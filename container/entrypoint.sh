#!/bin/sh

set -eu

# shellcheck source=/dev/null
. /opt/planet/container/lib/common.sh
# shellcheck source=/dev/null
. /opt/planet/container/lib/config.sh
# shellcheck source=/dev/null
. /opt/planet/container/lib/initialize.sh

load_config
initialize_runtime

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

log info "starting ZeroTier ${ZEROTIER_VERSION:-unknown}, ztncui ${ZTNCUI_COMMIT:-unknown}, and file service"
exec /usr/bin/supervisord --nodaemon --configuration /opt/planet/container/supervisord.conf
