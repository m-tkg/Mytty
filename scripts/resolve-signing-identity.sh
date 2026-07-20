#!/bin/sh

set -eu

if [ "${SIGN_IDENTITY+x}" = x ]; then
  printf '%s\n' "$SIGN_IDENTITY"
  exit 0
fi

identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
identity=$(
  printf '%s\n' "$identities" \
    | awk -F '"' '/"Developer ID Application:/ { print $2; exit }'
)
if [ -z "$identity" ]; then
  identity=$(
    printf '%s\n' "$identities" \
      | awk -F '"' '/"Apple Development:/ { print $2; exit }'
  )
fi

printf '%s\n' "$identity"
