#!/usr/bin/env bash

# Shared macOS bundle signing helpers. Callers must define SIGN_COMMON as the
# codesign arguments common to each nested item.

codesign_run() {
  if [[ "${CODESIGN_QUIET:-0}" == "1" ]]; then
    codesign "${SIGN_COMMON[@]}" "$@" >/dev/null
  else
    codesign "${SIGN_COMMON[@]}" "$@"
  fi
}

codesign_sign_framework_tree() {
  local framework="$1"
  while IFS= read -r executable; do
    codesign_run "${executable}"
  done < <(find "${framework}" -type f -perm -111 2>/dev/null | sort)

  while IFS= read -r bundle; do
    codesign_run "${bundle}"
  done < <(find "${framework}" \( -name '*.xpc' -o -name '*.app' \) -type d 2>/dev/null | sort -r)

  codesign_run "${framework}"
}

codesign_extension_entitlements() {
  local appex="$1"
  local project_root="${2:-$(pwd)}"
  case "$(basename "${appex}")" in
    widgetExtension.appex|PingScopeWidget.appex)
      echo "${project_root}/PingScopeWidget/PingScopeWidget.entitlements"
      ;;
    *)
      ;;
  esac
}

codesign_sign_extension() {
  local appex="$1"
  local project_root="${2:-$(pwd)}"
  case "$(basename "${appex}")" in
    widgetExtension.appex|PingScopeWidget.appex) ;;
    *)
      echo "Refusing to sign unexpected app extension: ${appex}" >&2
      return 2
      ;;
  esac
  while IFS= read -r framework; do
    codesign_sign_framework_tree "${framework}"
  done < <(find "${appex}/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | sort)
  while IFS= read -r dylib; do
    codesign_run "${dylib}"
  done < <(find "${appex}/Contents/MacOS" -name '*.dylib' -type f 2>/dev/null | sort)

  local entitlements
  entitlements="$(codesign_extension_entitlements "${appex}" "${project_root}")"
  if [[ -n "${entitlements}" ]]; then
    codesign_run --entitlements "${entitlements}" "${appex}"
  else
    codesign_run "${appex}"
  fi
}

codesign_sign_macos_bundle_contents() {
  local app_path="$1"
  local project_root="${2:-$(pwd)}"

  while IFS= read -r framework; do
    codesign_sign_framework_tree "${framework}"
  done < <(find "${app_path}/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | sort)

  while IFS= read -r dylib; do
    codesign_run "${dylib}"
  done < <(find "${app_path}/Contents/MacOS" -name '*.dylib' -type f 2>/dev/null | sort)

  while IFS= read -r appex; do
    codesign_sign_extension "${appex}" "${project_root}"
  done < <(find "${app_path}/Contents/PlugIns" -name '*.appex' -type d 2>/dev/null | sort)
}
