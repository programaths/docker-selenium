#!/usr/bin/env bash

# set -e: exit asap if a command exits with a non-zero status
set -e

echoerr() { awk " BEGIN { print \"$@\" > \"/dev/fd/2\" }" ; }

# Wait for this process dependencies
timeout --foreground ${WAIT_TIMEOUT} wait-xvfb.sh
timeout --foreground ${WAIT_TIMEOUT} wait-xmanager.sh
timeout --foreground ${WAIT_TIMEOUT} wait-selenium-hub.sh

JAVA_OPTS="$(java-dynamic-memory-opts.sh) ${JAVA_OPTS}"
echo "INFO: JAVA_OPTS are '${JAVA_OPTS}'"

# See standalone params docs at
#  https://code.google.com/p/selenium/wiki/Grid2
#  https://github.com/pilwon/selenium-webdriver/blob/master/java/server/src/org/openqa/grid/common/defaults/GridParameters.properties
# See node defaults at
#  https://github.com/pilwon/selenium-webdriver/blob/master/java/server/src/org/openqa/grid/common/defaults/DefaultNode.json
# TODO: how to set default firefox to latest?
java ${JAVA_OPTS} \
  -cp "${SEL_HOME}/selenium-server-standalone.jar:${SEL_HOME}/all-node-extensions.jar" "org.openqa.grid.selenium.GridLauncher" \
  -nodeConfig "${SEL_HOME}/sterodiumNodeConfig.json" \
  -port ${SELENIUM_NODE_SD_PORT} \
  -host ${SELENIUM_NODE_HOST} \
  -role node \
  -hub "${SELENIUM_HUB_PROTO}://${SELENIUM_HUB_HOST}:${SELENIUM_HUB_PORT}/grid/register" \
  -browser "${FIREFOX_BROWSER_CAPS}" \
  -trustAllSSLCertificates \
  -maxSession ${MAX_SESSIONS} \
  -timeout ${SEL_RELEASE_TIMEOUT_SECS} \
  -browserTimeout ${SEL_BROWSER_TIMEOUT_SECS} \
  -cleanUpCycle ${SEL_CLEANUPCYCLE_MS} \
  -nodePolling ${SEL_NODEPOLLING_MS} \
  -unregisterIfStillDownAfter ${SEL_UNREGISTER_IF_STILL_DOWN_AFTER} \
  ${SELENIUM_NODE_PARAMS} \
  ${CUSTOM_SELENIUM_NODE_PROXY_PARAMS} \
  ${CUSTOM_SELENIUM_NODE_REGISTER_CYCLE} \
  &
NODE_PID=$!

function shutdown {
  echo "-- INFO: Shutting down Firefox NODE gracefully..."
  kill -SIGINT ${NODE_PID} || true
  kill -SIGTERM ${NODE_PID} || true
  kill -SIGKILL ${NODE_PID} || true
  wait ${NODE_PID}
  echo "-- INFO: Firefox node shutdown complete."
  # First stop video recording because it needs some time to flush it
  supervisorctl -c /etc/supervisor/supervisord.conf stop video-rec || true
  killall supervisord
  exit 0
}

function trappedFn {
  echo "-- INFO: Trapped SIGTERM/SIGINT on Firefox NODE"
  shutdown
}
# Run function shutdown() when this process a killer signal
trap trappedFn SIGTERM SIGINT SIGKILL

# tells bash to wait until child processes have exited
wait ${NODE_PID}
echo "-- INFO: Passed after wait java Firefox node"

# Always shutdown if the node dies
shutdown

# Note to double pipe output and keep this process logs add at the end:
#  2>&1 | tee $SELENIUM_LOG
# But is no longer required because individual logs are maintained by
# supervisord right now.
