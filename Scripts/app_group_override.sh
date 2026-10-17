#!/bin/bash
# Source this file from either build path. No certificate or key is needed here.
app_group_build_args=()
if [[ -n "${COLORLIGHT_APP_GROUP:-}" ]]; then
  if [[ ! "$COLORLIGHT_APP_GROUP" =~ ^group\.[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    echo 'Invalid App Group identifier: expected group.<identifier>, not a path or shell expression.' >&2
    exit 2
  fi
  app_group_build_args=("COLORLIGHT_APP_GROUP=$COLORLIGHT_APP_GROUP")
fi
