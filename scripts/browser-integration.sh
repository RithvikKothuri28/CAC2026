#!/usr/bin/env bash
set -euo pipefail

# Called by firebase emulators:exec; tests also enforce this exact local project.
if [[ "${GCLOUD_PROJECT:-}" != "demo-farmtwin" || -z "${FIRESTORE_EMULATOR_HOST:-}" ]]; then
  echo 'Run this script inside demo-farmtwin emulators:exec.' >&2
  exit 1
fi
: "${CHROME_EXECUTABLE:?Supply the test Chrome executable}"
: "${CHROMEDRIVER_EXECUTABLE:?Supply its matching ChromeDriver executable}"
mkdir -p test-results
"$CHROMEDRIVER_EXECUTABLE" --port=4444 >test-results/chromedriver.log 2>&1 &
driver_pid=$!
trap 'kill "$driver_pid" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if curl --silent --fail http://127.0.0.1:4444/status >/dev/null; then break; fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:4444/status >/dev/null

for flow in production user; do
  flutter drive --driver=test_driver/integration_test.dart \
    --target="integration_test/${flow}_flow_test.dart" \
    -d web-server --browser-name=chrome --headless \
    --chrome-binary="$CHROME_EXECUTABLE" \
    --dart-define-from-file=config/development.example.json \
    2>&1 | tee "test-results/${flow}-integration.log"
done
