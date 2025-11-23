#!/usr/bin/env bash

# automation_webhook_post_build.sh
# Called from CodeBuild post_build phase to send intake-wise status to backend webhook.

echo "[INFO] CodeBuild post_build webhook script started"

# 1) No intakes case
if [ -f /tmp/no_intakes ]; then
  echo "[INFO] /tmp/no_intakes found. No intake_id_* folders were detected. Skipping webhook."
  exit 0
fi

# 2) Locate base sandbox directory
if [ -z "${CODEBUILD_SRC_DIR:-}" ]; then
  echo "[ERROR] CODEBUILD_SRC_DIR is not set. Cannot resolve Sandbox-Infra path."
  exit 1
fi

BASE_DIR="$CODEBUILD_SRC_DIR/Sandbox-Infra/live/sandbox"
if [ ! -d "$BASE_DIR" ]; then
  echo "[ERROR] Base directory $BASE_DIR not found in post_build."
  exit 1
fi

echo "[INFO] Using base directory: $BASE_DIR"

# 3) Determine global pipeline status from CodeBuild
if [ "${CODEBUILD_BUILD_SUCCEEDING:-0}" -eq 1 ]; then
  PIPELINE_STATUS="SUCCEEDED"
else
  PIPELINE_STATUS="FAILED"
fi
echo "[INFO] CodeBuild pipeline_status=$PIPELINE_STATUS"

# 4) Webhook URL (can be overridden by environment variable if needed)
WEBHOOK_URL="${WEBHOOK_URL:-https://api.dev.aisandbox.wbd.com/automation_webhook}"
echo "[INFO] Webhook URL set to: $WEBHOOK_URL"

# 5) Iterate all intake IDs captured earlier
if [ ! -f /tmp/intakes.txt ]; then
  echo "[ERROR] /tmp/intakes.txt not found. Cannot determine intake IDs to process."
  exit 1
fi

while read -r INTAKE_ID; do
  [ -z "$INTAKE_ID" ] && continue

  echo "------------------------------"
  echo "[INFO] Processing intake folder: $INTAKE_ID"

  JSON_PATH="$BASE_DIR/$INTAKE_ID/inputs.json"
  if [ ! -f "$JSON_PATH" ]; then
    echo "[WARN] inputs.json not found for $INTAKE_ID at $JSON_PATH. Skipping this intake."
    continue
  fi

  # 6) Read inputs.json values
  REQUEST_ID=$(jq -r '.request_id' "$JSON_PATH")
  AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$JSON_PATH")
  SANDBOX_NAME=$(jq -r '.sandbox_name' "$JSON_PATH")
  IS_MODIFIED=$(jq -r '.isModified // false' "$JSON_PATH")
  IS_EXTENDED=$(jq -r '.isExtended // false' "$JSON_PATH")
  IS_DECOMMISSION=$(jq -r '.isDecommission // false' "$JSON_PATH")

  echo "[INFO] Intake $INTAKE_ID: request_id=$REQUEST_ID, aws_account_id=$AWS_ACCOUNT_ID, sandbox_name=$SANDBOX_NAME, isModified=$IS_MODIFIED, isExtended=$IS_EXTENDED, isDecommission=$IS_DECOMMISSION"

  # 7) Derive request_type (decommission overrides everything)
  if [ "$IS_DECOMMISSION" = "true" ]; then
    REQUEST_TYPE="decommission"
  elif [ "$IS_MODIFIED" = "false" ]; then
    REQUEST_TYPE="new"
  elif [ "$IS_EXTENDED" = "true" ]; then
    REQUEST_TYPE="extended"
  else
    REQUEST_TYPE="modified"
  fi

  echo "[INFO] Intake $INTAKE_ID: derived request_type=$REQUEST_TYPE"

  # 8) Derive provisioning_status
  if [ "$REQUEST_TYPE" = "decommission" ]; then
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      PROVISIONING_STATUS="DECOMMISSION_COMPLETED"
    else
      PROVISIONING_STATUS="DECOMMISSION_FAILED"
    fi
  else
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      PROVISIONING_STATUS="PROVISIONING_COMPLETED"
    else
      if [ "$REQUEST_TYPE" = "new" ]; then
        PROVISIONING_STATUS="PROVISIONING_FAILED_FIRST_ATTEMPT"
      else
        PROVISIONING_STATUS="PROVISIONING_PARTIALLY_COMPLETED"
      fi
    fi
  fi

  echo "[INFO] Intake $INTAKE_ID: provisioning_status=$PROVISIONING_STATUS"

  # 9) Derive lifecycle_status and lifecycle_message
  # Rules:
  # - New + success: ACTIVE; fail: FAILED
  # - Modified / Extended: always ACTIVE, even on failure
  # - Decommission: ACTIVE for backup window, both success and failure

  if [ "$REQUEST_TYPE" = "new" ]; then
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="New sandbox provisioned and active."
    else
      LIFECYCLE_STATUS="FAILED"
      LIFECYCLE_MESSAGE="New sandbox provisioning failed; no stable environment created."
    fi
  elif [ "$REQUEST_TYPE" = "modified" ]; then
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Sandbox active; configuration changes applied successfully."
    else
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Sandbox active; modification partially failed, manual review required."
    fi
  elif [ "$REQUEST_TYPE" = "extended" ]; then
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Sandbox active; lease extended."
    else
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Sandbox active; lease extension failed, previous lease still effective."
    fi
  else  # decommission
    if [ "$PIPELINE_STATUS" = "SUCCEEDED" ]; then
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Decommission completed; account active only for backup retention period."
    else
      LIFECYCLE_STATUS="ACTIVE"
      LIFECYCLE_MESSAGE="Decommission failed; sandbox still active, manual cleanup required."
    fi
  fi

  echo "[INFO] Intake $INTAKE_ID: lifecycle_status=$LIFECYCLE_STATUS, lifecycle_message=\"$LIFECYCLE_MESSAGE\""

  # 10) Build payload
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  PAYLOAD=$(jq -n \
    --arg intake_id "$REQUEST_ID" \
    --arg aws_account_id "$AWS_ACCOUNT_ID" \
    --arg sandbox_name "$SANDBOX_NAME" \
    --arg request_type "$REQUEST_TYPE" \
    --arg provisioning_status "$PROVISIONING_STATUS" \
    --arg pipeline_status "$PIPELINE_STATUS" \
    --arg lifecycle_status "$LIFECYCLE_STATUS" \
    --arg lifecycle_message "$LIFECYCLE_MESSAGE" \
    --arg build_id "${CODEBUILD_BUILD_ID:-unknown}" \
    --arg timestamp "$TS" \
    '{
      intake_id: $intake_id,
      aws_account_id: $aws_account_id,
      sandbox_name: $sandbox_name,
      request_type: $request_type,
      provisioning_status: $provisioning_status,
      pipeline_status: $pipeline_status,
      lifecycle_status: $lifecycle_status,
      lifecycle_message: $lifecycle_message,
      build_id: $build_id,
      timestamp: $timestamp
    }')

  echo "[INFO] Intake $INTAKE_ID: webhook payload = $PAYLOAD"

  # 11) Call webhook with clear HTTP logging
  RESP_FILE="/tmp/webhook_resp_${INTAKE_ID}.json"

  echo "[INFO] Intake $INTAKE_ID: calling webhook at $WEBHOOK_URL"

  HTTP_INFO=$(curl -s -o "$RESP_FILE" -w 'HTTP_CODE=%{http_code}' \
    "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" )

  HTTP_CODE="${HTTP_INFO#HTTP_CODE=}"

  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "[INFO] Intake $INTAKE_ID: webhook succeeded (HTTP $HTTP_CODE)"
  else
    echo "[ERROR] Intake $INTAKE_ID: webhook failed (HTTP $HTTP_CODE)"
    echo "[ERROR] Intake $INTAKE_ID: webhook response body:"
    if [ -s "$RESP_FILE" ]; then
      cat "$RESP_FILE"
    else
      echo "[ERROR] Intake $INTAKE_ID: no response body received."
    fi
    exit 1
  fi

done < /tmp/intakes.txt

echo "[INFO] CodeBuild post_build webhook script completed successfully"
