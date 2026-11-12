# shellcheck shell=bash
# Shared macOS toolchain setup for Bandwagon scripts.
# Prefer an existing DEVELOPER_DIR, then `xcode-select -p`, then default Xcode.app.
xcode_env() {
  if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if developer="$(xcode-select -p 2>/dev/null)"; then
      DEVELOPER_DIR="$developer"
    elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
      printf 'Set DEVELOPER_DIR or install Xcode (xcode-select --install is not enough for packaging)\n' >&2
      return 1
    fi
  fi
  export DEVELOPER_DIR
  export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
  if ! SDKROOT="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"; then
    printf 'macOS SDK missing (DEVELOPER_DIR=%s)\n' "$DEVELOPER_DIR" >&2
    return 1
  fi
  export SDKROOT
  [[ -d "$SDKROOT" ]] || {
    printf 'macOS SDK path invalid: %s\n' "$SDKROOT" >&2
    return 1
  }
}
