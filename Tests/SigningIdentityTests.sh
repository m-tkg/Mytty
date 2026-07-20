#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
resolver="$root/scripts/resolve-signing-identity.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

cat > "$temporary/security" <<'EOF'
#!/bin/sh
case "${IDENTITY_FIXTURE:-none}" in
  both)
    cat <<'IDENTITIES'
  1) AAAA "Apple Development: Developer (TEAMDEV)"
  2) BBBB "Developer ID Application: Developer (TEAMDIST)"
     2 valid identities found
IDENTITIES
    ;;
  development)
    cat <<'IDENTITIES'
  1) AAAA "Apple Development: Developer (TEAMDEV)"
     1 valid identities found
IDENTITIES
    ;;
  fail)
    exit 99
    ;;
  *)
    echo "     0 valid identities found"
    ;;
esac
EOF
chmod +x "$temporary/security"

test -x "$resolver"

actual=$(
  env -u SIGN_IDENTITY \
    PATH="$temporary:$PATH" \
    IDENTITY_FIXTURE=both \
    "$resolver"
)
test "$actual" = "Developer ID Application: Developer (TEAMDIST)"

actual=$(
  env -u SIGN_IDENTITY \
    PATH="$temporary:$PATH" \
    IDENTITY_FIXTURE=development \
    "$resolver"
)
test "$actual" = "Apple Development: Developer (TEAMDEV)"

actual=$(
  SIGN_IDENTITY="Explicit Signing Identity" \
    PATH="$temporary:$PATH" \
    IDENTITY_FIXTURE=fail \
    "$resolver"
)
test "$actual" = "Explicit Signing Identity"

actual=$(
  SIGN_IDENTITY= \
    PATH="$temporary:$PATH" \
    IDENTITY_FIXTURE=fail \
    "$resolver"
)
test -z "$actual"

actual=$(
  env -u SIGN_IDENTITY \
    PATH="$temporary:$PATH" \
    IDENTITY_FIXTURE=none \
    "$resolver"
)
test -z "$actual"

printf 'Signing identity selection passed\n'
