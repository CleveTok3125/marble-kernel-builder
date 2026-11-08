#!/usr/bin/env bash
# Kconfig helpers for manager-side SUSFS integration.

# ensure_susfs_priority_uid_filter declares CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER
# in a manager Kconfig that lacks it.
#
# SukiSU Ultra's builtin branch calls susfs_parse_priority_app_strings() and
# susfs_set_priority_uid_filter() unconditionally, while fs/susfs.c and
# include/linux/susfs.h only expose them under that option. The option is
# declared by susfs4ksu's KernelSU manager patch, which this builder does not
# apply because managers ship their own SUSFS support. Without the declaration
# the manager build fails on implicit function declarations (-Werror).
#
# No-op when the option already exists or when the manager never references the
# helpers.
ensure_susfs_priority_uid_filter() {
  local kconfig="$1"
  local manager_dir="$2"

  if grep -q '^config KSU_SUSFS_PRIORITY_UID_FILTER$' "${kconfig}"; then
    return 0
  fi
  if ! grep -rqE 'susfs_(parse_priority_app_strings|set_priority_uid_filter)' "${manager_dir}"; then
    return 0
  fi

  local stanza
  stanza="$(printf '%s\n' \
    'config KSU_SUSFS_PRIORITY_UID_FILTER' \
    $'\tbool "Enable to allow adding user-defined uids that will be hidden from getpriority/setpriority/ioprio_get/ioprio_set syscall"' \
    $'\tdepends on KSU_SUSFS' \
    $'\tdefault y' \
    $'\thelp' \
    $'\t  - Allow hiding user-defined uids from syscalls like getpriority/setpriority/ioprio_get/ioprio_set.' \
    $'\t  - Effective on all processes with uid >= 10000.')"

  # Close of the SUSFS menu; entries are inserted just before it so the option
  # keeps the same scope as the rest of the manager-side SUSFS settings.
  local menu_end
  menu_end="$(awk '
      /^menu "KernelSU - SUSFS"/ { in_menu = 1; next }
      in_menu && /^endmenu$/ { print NR; exit }
    ' "${kconfig}")"

  if [[ -z "${menu_end}" ]]; then
    # Unknown layout: a top-level entry still resolves the symbol.
    printf '%s\n\n' "${stanza}" >> "${kconfig}"
    echo "Declared CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER at the end of ${kconfig}"
    return 0
  fi

  # Keep one blank line of separation on both sides.
  local insert_at="${menu_end}" skip_blank=0
  if [[ "$(sed -n "$((menu_end - 1))p" "${kconfig}")" =~ ^[[:space:]]*$ ]]; then
    insert_at=$((menu_end - 1))
    skip_blank=1
  fi

  local tmp="${kconfig}.susfs.$$"
  awk -v at="${insert_at}" -v skip="${skip_blank}" -v stanza="${stanza}" '
      NR == at { print stanza; print ""; if (skip) next }
      { print }
    ' "${kconfig}" > "${tmp}"
  mv "${tmp}" "${kconfig}"
  echo "Declared CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER in ${kconfig}"
}
