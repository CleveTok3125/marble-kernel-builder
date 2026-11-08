#!/usr/bin/env bash
# Kconfig fallback tests for manager-side SUSFS integration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

source scripts/lib/susfs-kconfig.sh

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_susfs_menu_manager() {
  local dir="$1"
  mkdir -p "${dir}"
  cat > "${dir}/Kconfig" <<'EOF'
menu "KernelSU"

menu "KernelSU - SUSFS"
config KSU_SUSFS
	bool "KernelSU addon - SUSFS"
	default y
endmenu

endmenu
EOF
  cat > "${dir}/ksu.c" <<'EOF'
void ksu_track_throne(void) { susfs_parse_priority_app_strings(); }
EOF
}

# 1. Manager calls the SUSFS priority helpers: option is declared inside the
#    SUSFS menu, with the upstream defaults.
write_susfs_menu_manager "${tmp}/needs"
ensure_susfs_priority_uid_filter "${tmp}/needs/Kconfig" "${tmp}/needs" >/dev/null

kconfig="${tmp}/needs/Kconfig"
declarations="$(grep -c '^config KSU_SUSFS_PRIORITY_UID_FILTER$' "${kconfig}")"
[[ "${declarations}" == "1" ]] || fail "expected one declaration, got ${declarations}"
grep -q '^	depends on KSU_SUSFS$' "${kconfig}" || fail "missing depends on KSU_SUSFS"
grep -q '^	default y$' "${kconfig}" || fail "missing default y"

menu_line="$(grep -n '^menu "KernelSU - SUSFS"$' "${kconfig}" | cut -d: -f1)"
config_line="$(grep -n '^config KSU_SUSFS_PRIORITY_UID_FILTER$' "${kconfig}" | cut -d: -f1)"
end_line="$(awk -v start="${menu_line}" 'NR > start && /^endmenu$/ { print NR; exit }' "${kconfig}")"
[[ "${config_line}" -gt "${menu_line}" ]] || fail "declaration must follow the SUSFS menu"
[[ "${config_line}" -lt "${end_line}" ]] || fail "declaration must stay inside the SUSFS menu"
if ! awk '
    /^[[:space:]]*$/ { if (++blank > 1) bad = 1; next }
    { blank = 0 }
    END { exit bad }
  ' "${kconfig}"; then
  fail "insertion must not create consecutive blank lines"
fi

# 2. Re-running must not duplicate the declaration.
cp "${kconfig}" "${tmp}/needs.expected"
ensure_susfs_priority_uid_filter "${kconfig}" "${tmp}/needs" >/dev/null
cmp -s "${kconfig}" "${tmp}/needs.expected" || fail "second run changed the Kconfig"

# 3. Manager without the helper call sites: Kconfig is left untouched.
write_susfs_menu_manager "${tmp}/unrelated"
cat > "${tmp}/unrelated/ksu.c" <<'EOF'
void ksu_track_throne(void) { }
EOF
cp "${tmp}/unrelated/Kconfig" "${tmp}/unrelated.expected"
ensure_susfs_priority_uid_filter "${tmp}/unrelated/Kconfig" "${tmp}/unrelated" >/dev/null
cmp -s "${tmp}/unrelated/Kconfig" "${tmp}/unrelated.expected" || fail "unrelated manager must not change Kconfig"

# 4. Kconfig that already declares the option: no duplicate.
write_susfs_menu_manager "${tmp}/declared"
printf '%s\n' 'config KSU_SUSFS_PRIORITY_UID_FILTER' > "${tmp}/declared/Kconfig"
cat >> "${tmp}/declared/Kconfig" <<'EOF'
	bool "already there"
	depends on KSU_SUSFS
	default y
EOF
cp "${tmp}/declared/Kconfig" "${tmp}/declared.expected"
ensure_susfs_priority_uid_filter "${tmp}/declared/Kconfig" "${tmp}/declared" >/dev/null
cmp -s "${tmp}/declared/Kconfig" "${tmp}/declared.expected" || fail "existing declaration must not be duplicated"

# 5. Unknown menu layout: entry is appended so the symbol still resolves.
mkdir -p "${tmp}/flat"
cat > "${tmp}/flat/Kconfig" <<'EOF'
config KSU
	bool "KernelSU"
	default y
EOF
cat > "${tmp}/flat/ksu.c" <<'EOF'
void ksu_dispatch(void) { susfs_set_priority_uid_filter(arg); }
EOF
ensure_susfs_priority_uid_filter "${tmp}/flat/Kconfig" "${tmp}/flat" >/dev/null
grep -q '^config KSU_SUSFS_PRIORITY_UID_FILTER$' "${tmp}/flat/Kconfig" || fail "fallback append missing declaration"
awk 'NF { last = $0 } END { print last }' "${tmp}/flat/Kconfig" | grep -q 'uid >= 10000' || fail "fallback append is incomplete"

echo "SUSFS Kconfig tests passed"
