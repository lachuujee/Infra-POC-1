#!/usr/bin/env bash
# automation_webhook_post_build.sh

echo "[INFO] CodeBuild post_build webhook script started"

# 1) No intakes → nothing to send
if [ -f /tmp/no_intakes ]; then
  echo "[INFO] /tmp/no_intakes found. No intake_id_* folders were detected. Skipping webhook."
  exit 0
fi

# 2) Resolve base directory
if [ -z "${CODEBUILD_SRC_DIR:-}" ]; then
  echo "[ERROR] CODEBUILD_SRC_DIR is not set. Cannot resolve Sandbox-Infra path."
  exit 1
fi

BASE_DIR="${CODEBUILD_SRC_DIR}/Sandbox-Infra/live/sandbox"
if [ ! -d "$BASE_DIR" ]; then
  echo "[ERROR] Base directory $BASE_DIR not found in post_build."
  exit 1
fi

# 3) Global pipeline status from CodeBuild
if [ "${CODEBUILD_BUILD_SUCCEEDING}" -eq 1 ]; then
  PIPELINE_STATUS="SUCCEEDED"
else
  PIPELINE_STATUS="FAILED"
fi

# Map overall pipeline status to backend provisioning_status (ACTIVE/PENDING/ARCHIVED)
if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
  BACKEND_PROVISIONING_STATUS="ACTIVE"
else
  BACKEND_PROVISIONING_STATUS="PENDING"
fi

if [ ! -f /tmp/intakes.txt ]; then
  echo "[WARN] /tmp/intakes.txt not found. Nothing to send to webhook."
  exit 0
fi

# 4) Per-intake processing
while read -r INTAKE_ID; do
  [ -z "$INTAKE_ID" ] && continue

  echo "[INFO] Processing intake in webhook script: $INTAKE_ID"

  JSON_PATH="${BASE_DIR}/${INTAKE_ID}/inputs.json"
  if [ ! -f "$JSON_PATH" ]; then
    echo "[WARN] inputs.json not found for $INTAKE_ID at $JSON_PATH, skipping."
    continue
  fi

  REQUEST_ID=$(jq -r '.request_id' "$JSON_PATH")
  AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$JSON_PATH")
  SANDBOX_NAME=$(jq -r '.sandbox_name' "$JSON_PATH")
  IS_MODIFIED=$(jq -r '.isModified // false' "$JSON_PATH")
  IS_EXTENDED=$(jq -r '.isExtended // false' "$JSON_PATH")
  IS_DECOMMISSION=$(jq -r '.isDecommission // false' "$JSON_PATH")

  # Request type mapping for backend enum
  if [ "$IS_DECOMMISSION" = "true" ]; then
    BACKEND_TYPE="decommission"
  elif [ "$IS_EXTENDED" = "true" ]; then
    BACKEND_TYPE="extend_request"
  else
    BACKEND_TYPE="new_sandbox"
  fi

  # Detailed pipeline result for logging only
  if [ "$BACKEND_TYPE" = "decommission" ]; then
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      PIPELINE_RESULT="DECOMMISSION_COMPLETED"
    else
      PIPELINE_RESULT="DECOMMISSION_FAILED"
    fi
  else
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      PIPELINE_RESULT="PROVISIONING_COMPLETED"
    else
      if [ "$IS_MODIFIED" = "false" ]; then
        PIPELINE_RESULT="PROVISIONING_FAILED_FIRST_ATTEMPT"
      else
        PIPELINE_RESULT="PROVISIONING_PARTIALLY_COMPLETED"
      fi
    fi
  fi

  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  TRACE_ID="cb-${REQUEST_ID}-$(date +%s)"

  PAYLOAD=$(jq -n \
    --arg request_id "$REQUEST_ID" \
    --arg sandbox_name "$SANDBOX_NAME" \
    --arg type "$BACKEND_TYPE" \
    --arg provisioning_status "$BACKEND_PROVISIONING_STATUS" \
    --arg aws_account_id "$AWS_ACCOUNT_ID" \
    --arg pipeline_result "$PIPELINE_RESULT" \
    --arg pipeline_status "$PIPELINE_STATUS" \
    --arg build_id "$CODEBUILD_BUILD_ID" \
    --arg timestamp "$TS" \
    '{
      request_id: $request_id,
      sandbox_name: $sandbox_name,
      type: $type,
      provisioning_status: $provisioning_status,
      aws_account_id: $aws_account_id,
      pipeline_result: $pipeline_result,
      pipeline_status: $pipeline_status,
      build_id: $build_id,
      timestamp: $timestamp
    }')

  echo "[INFO] Webhook payload for $INTAKE_ID (trace_id=$TRACE_ID): $PAYLOAD"

  RESP_FILE="/tmp/webhook_${INTAKE_ID}.json"

  curl -sS -m 20 --connect-timeout 5 \
    -w "\n[INFO] webhook http_code=%{http_code} time_total=%{time_total}s\n" \
    -H "Content-Type: application/json" \
    -H "X-Trace-Id: ${TRACE_ID}" \
    -o "$RESP_FILE" \
    -X POST "https://api.dev.aisandbox.wbd.com/automation_webhook" \
    -d "$PAYLOAD"

  CURL_EXIT=$?

  echo "[INFO] Webhook response for $INTAKE_ID (trace_id=$TRACE_ID):"
  if [ -s "$RESP_FILE" ]; then
    cat "$RESP_FILE"
    echo
  else
    echo "[INFO] Response body is empty."
  fi

  if [ $CURL_EXIT -ne 0 ]; then
    echo "[ERROR] Webhook call failed for $INTAKE_ID with exit code $CURL_EXIT"
    exit 1
  fi

  echo "[INFO] Webhook call succeeded for $INTAKE_ID (trace_id=$TRACE_ID)"

done < /tmp/intakes.txt

echo "[INFO] Completed post_build webhook script successfully"
