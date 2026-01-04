#!/bin/bash
# Query CPU package temperatures from all hosts

echo "==> CPU Package Temperatures"
echo ""

curl -s 'http://victoria-metrics.pw.internal:8428/api/v1/query?query=sensors_temp_input' 2>/dev/null | \
  jq -r '.data.result[] | select(.metric.chip | contains("coretemp")) | select(.metric.feature == "package_id_0") | "\(.metric.host): \(.value[1])°C"' | \
  sort

echo ""
