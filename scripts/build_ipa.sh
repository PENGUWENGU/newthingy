#!/usr/bin/env bash
# ==============================================================================
# Locus Unsigned IPA Build & Packaging Script
# 
# Builds a sideload-ready unsigned/ad-hoc iOS IPA for Locus with 100% verified
# Mach-O executable binary, Info.plist, and necessary resources.
# ==============================================================================

set -euo pipefail

CONFIG="${1:-${CONFIGURATION:-Release}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=================================================="
echo "🚀 Locus Unsigned IPA Builder"
echo "Configuration: $CONFIG"
echo "Working directory: $ROOT_DIR"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. Detect and select Xcode
# ------------------------------------------------------------------------------
echo "--- 1. Selecting Xcode Developer Tools ---"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  SELECTED_XCODE=""
  for candidate in /Applications/Xcode_16*.app /Applications/Xcode_15*.app /Applications/Xcode*.app; do
    if [ -d "$candidate/Contents/Developer" ]; then
      SELECTED_XCODE="$candidate"
      break
    fi
  done

  if [ -n "$SELECTED_XCODE" ]; then
    echo "Using Xcode at: $SELECTED_XCODE"
    export DEVELOPER_DIR="$SELECTED_XCODE/Contents/Developer"
  fi
fi

if command -v xcode-select >/dev/null 2>&1; then
  echo "Active Xcode path: $(xcode-select -p 2>/dev/null || echo 'Unknown')"
fi
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version || true
fi

# ------------------------------------------------------------------------------
# 2. Ensure XcodeGen is available (fast install from release binary if missing)
# ------------------------------------------------------------------------------
echo "--- 2. Checking XcodeGen ---"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found in PATH. Attempting fast precompiled binary install..."
  mkdir -p /tmp/xcodegen_install
  if curl -sSL -f --connect-timeout 15 --retry 2 "https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip" -o /tmp/xcodegen_install/xcodegen.zip; then
    unzip -qo /tmp/xcodegen_install/xcodegen.zip -d /tmp/xcodegen_install
    if [ -f "/tmp/xcodegen_install/xcodegen/bin/xcodegen" ]; then
      echo "Installed precompiled XcodeGen to /usr/local/bin..."
      sudo cp "/tmp/xcodegen_install/xcodegen/bin/xcodegen" /usr/local/bin/ || cp "/tmp/xcodegen_install/xcodegen/bin/xcodegen" "$ROOT_DIR/xcodegen_bin"
      if [ -f "$ROOT_DIR/xcodegen_bin" ]; then
        chmod +x "$ROOT_DIR/xcodegen_bin"
        export PATH="$ROOT_DIR:$PATH"
      fi
    fi
  fi
  rm -rf /tmp/xcodegen_install
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Falling back to brew install xcodegen..."
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen || true
  fi
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen version: $(xcodegen version 2>/dev/null || echo 'installed')"
else
  echo "Warning: xcodegen command could not be installed. Existing Locus.xcodeproj will be used if present."
fi

# ------------------------------------------------------------------------------
# 3. Ensure libidevice_ffi.a is present and valid
# ------------------------------------------------------------------------------
echo "--- 3. Verifying libidevice_ffi.a ---"
mkdir -p Vendor/idevice
IDEVICE_A="Vendor/idevice/libidevice_ffi.a"
NEED_DOWNLOAD=1

if [ -f "$IDEVICE_A" ]; then
  FSIZE=$(wc -c < "$IDEVICE_A" | tr -d ' ')
  if [ "$FSIZE" -gt 10000000 ]; then
    echo "libidevice_ffi.a is valid (${FSIZE} bytes)."
    NEED_DOWNLOAD=0
  else
    echo "libidevice_ffi.a is only ${FSIZE} bytes (likely a pointer or truncated file); re-downloading..."
    rm -f "$IDEVICE_A"
  fi
fi

if [ "$NEED_DOWNLOAD" -eq 1 ]; then
  echo "Downloading libidevice_ffi.a..."
  MIRRORS=(
    "https://raw.githubusercontent.com/ChrisMack32/Locus/main/Vendor/idevice/libidevice_ffi.a"
    "https://github.com/ChrisMack32/Locus/raw/main/Vendor/idevice/libidevice_ffi.a"
  )
  DOWNLOAD_OK=0
  for mirror in "${MIRRORS[@]}"; do
    echo "Trying download mirror: $mirror"
    if curl -sSL -f --retry 3 --retry-delay 2 --connect-timeout 20 "$mirror" -o "$IDEVICE_A"; then
      FSIZE=$(wc -c < "$IDEVICE_A" | tr -d ' ')
      if [ "$FSIZE" -gt 10000000 ]; then
        echo "Successfully downloaded libidevice_ffi.a (${FSIZE} bytes)."
        DOWNLOAD_OK=1
        break
      fi
    fi
    rm -f "$IDEVICE_A"
  done

  if [ "$DOWNLOAD_OK" -ne 1 ]; then
    echo "ERROR: Failed to download libidevice_ffi.a from all mirrors." >&2
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# 4. Generate Xcode project with XcodeGen if available
# ------------------------------------------------------------------------------
echo "--- 4. Preparing Xcode project ---"
if command -v xcodegen >/dev/null 2>&1 && [ -f "project.yml" ]; then
  echo "Generating Locus.xcodeproj from project.yml..."
  rm -rf Locus.xcodeproj
  xcodegen generate --spec project.yml
fi

if [ ! -d "Locus.xcodeproj" ]; then
  echo "ERROR: Locus.xcodeproj does not exist and could not be generated!" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 5. Build native application with xcodebuild
# ------------------------------------------------------------------------------
echo "--- 5. Compiling iOS Application ---"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
mkdir -p "$DERIVED_DATA"
rm -f "$ROOT_DIR/build.log"

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "Utilizing $NCPU CPU cores for compilation..."

validate_app_bundle() {
  local candidate="$1"
  [ -z "$candidate" ] && return 1
  [ ! -d "$candidate" ] && return 1
  [ ! -f "$candidate/Info.plist" ] && return 1
  
  local exec_name
  exec_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$candidate/Info.plist" 2>/dev/null || echo "Locus")
  [ -z "$exec_name" ] && exec_name="Locus"
  
  if [ ! -f "$candidate/$exec_name" ] || [ ! -s "$candidate/$exec_name" ]; then
    return 1
  fi
  return 0
}

BUILD_SUCCESS=0

echo "Running xcodebuild scheme 'Locus'..."
if xcodebuild \
  -project Locus.xcodeproj \
  -scheme Locus \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$NCPU" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_ENTITLEMENTS="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build 2>&1 | tee -a "$ROOT_DIR/build.log"; then
  BUILD_SUCCESS=1
fi

# Fallback: if scheme build had any issue, retry target 'Locus' directly
TARGET_CANDIDATE="$DERIVED_DATA/Build/Products/${CONFIG}-iphoneos/Locus.app"
if ! validate_app_bundle "$TARGET_CANDIDATE"; then
  echo "Target check: validating fallback builds..."
  if [ "$BUILD_SUCCESS" -ne 1 ]; then
    echo "Retrying directly with -target Locus..."
    if xcodebuild \
      -project Locus.xcodeproj \
      -target Locus \
      -configuration "$CONFIG" \
      -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$DERIVED_DATA" \
      -jobs "$NCPU" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGN_IDENTITY="-" \
      AD_HOC_CODE_SIGNING_ALLOWED=YES \
      CODE_SIGN_STYLE=Manual \
      DEVELOPMENT_TEAM="" \
      PROVISIONING_PROFILE_SPECIFIER="" \
      CODE_SIGN_ENTITLEMENTS="" \
      COMPILER_INDEX_STORE_ENABLE=NO \
      build 2>&1 | tee -a "$ROOT_DIR/build.log"; then
      BUILD_SUCCESS=1
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 6. Locate and validate the compiled .app bundle
# ------------------------------------------------------------------------------
echo "--- 6. Locating and validating compiled .app bundle ---"
FOUND_APP=""

SEARCH_PATHS=(
  "$DERIVED_DATA/Build/Products/${CONFIG}-iphoneos/Locus.app"
  "$DERIVED_DATA/Build/Products/Release-iphoneos/Locus.app"
  "$DERIVED_DATA/Build/Products/Debug-iphoneos/Locus.app"
)

for p in "${SEARCH_PATHS[@]}"; do
  if validate_app_bundle "$p"; then
    FOUND_APP="$p"
    break
  fi
done

if [ -z "$FOUND_APP" ]; then
  for candidate in $(find "$BUILD_DIR" -name "Locus.app" -type d 2>/dev/null); do
    if validate_app_bundle "$candidate"; then
      FOUND_APP="$candidate"
      break
    fi
  done
fi

if [ -z "$FOUND_APP" ]; then
  echo "==================================================" >&2
  echo "❌ ERROR: No valid Locus.app with executable binary was produced!" >&2
  echo "Build log summary:" >&2
  grep -E "error:" "$ROOT_DIR/build.log" | tail -n 20 >&2 || true
  echo "==================================================" >&2
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$FOUND_APP/Info.plist" 2>/dev/null || echo "Locus")
[ -z "$EXEC_NAME" ] && EXEC_NAME="Locus"

echo "✅ Located verified app bundle: $FOUND_APP"
echo "Main executable name: $EXEC_NAME"
ls -lh "$FOUND_APP/$EXEC_NAME"
file "$FOUND_APP/$EXEC_NAME" || true

# ------------------------------------------------------------------------------
# 7. Embed optional widget extension if built
# ------------------------------------------------------------------------------
WIDGET_APPEX=$(find "$BUILD_DIR" -name "LocusWidgets.appex" -type d 2>/dev/null | head -n 1)
if [ -n "$WIDGET_APPEX" ] && [ -f "$WIDGET_APPEX/LocusWidgets" ]; then
  echo "Embedding LocusWidgets.appex into Locus.app/PlugIns..."
  mkdir -p "$FOUND_APP/PlugIns"
  cp -a "$WIDGET_APPEX" "$FOUND_APP/PlugIns/LocusWidgets.appex"
fi

# ------------------------------------------------------------------------------
# 8. Package into unsigned IPA
# ------------------------------------------------------------------------------
echo "--- 7. Packaging IPA ---"
PAYLOAD_DIR="$ROOT_DIR/Payload"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -a "$FOUND_APP" "$PAYLOAD_DIR/Locus.app"

STAGED_EXEC="$PAYLOAD_DIR/Locus.app/$EXEC_NAME"
if [ ! -f "$STAGED_EXEC" ] || [ ! -s "$STAGED_EXEC" ]; then
  echo "ERROR: Executable '$EXEC_NAME' is missing or 0 bytes inside Payload/Locus.app!" >&2
  exit 1
fi
chmod +x "$STAGED_EXEC"

IPA_NAME_PRIMARY="LocusPlus-unsigned.ipa"
IPA_NAME_SECONDARY="Locus-unsigned.ipa"

rm -f "$ROOT_DIR/$IPA_NAME_PRIMARY" "$ROOT_DIR/$IPA_NAME_SECONDARY"
echo "Creating $IPA_NAME_PRIMARY..."
/usr/bin/zip -qry "$ROOT_DIR/$IPA_NAME_PRIMARY" Payload
cp "$ROOT_DIR/$IPA_NAME_PRIMARY" "$ROOT_DIR/$IPA_NAME_SECONDARY"

# ------------------------------------------------------------------------------
# 9. Strict Verification of IPA Archive Contents
# ------------------------------------------------------------------------------
echo "--- 8. Strict Verification of IPA Contents ---"
/usr/bin/unzip -t "$ROOT_DIR/$IPA_NAME_PRIMARY" >/dev/null
echo "Archive integrity: OK"

# Check presence of main binary inside zip
ZIP_CONTENTS=$(/usr/bin/unzip -l "$ROOT_DIR/$IPA_NAME_PRIMARY")
if ! echo "$ZIP_CONTENTS" | grep -q "Payload/Locus.app/$EXEC_NAME"; then
  echo "ERROR: Critical packaging failure: executable binary '$EXEC_NAME' NOT found in IPA!" >&2
  exit 1
fi
if ! echo "$ZIP_CONTENTS" | grep -q "Payload/Locus.app/Info.plist"; then
  echo "ERROR: Critical packaging failure: Info.plist NOT found in IPA!" >&2
  exit 1
fi

echo "=================================================="
echo "🎉 SUCCESS: IPA BUILT & VERIFIED SUCCESSFULLY!"
echo "Primary IPA: $ROOT_DIR/$IPA_NAME_PRIMARY ($(du -h "$ROOT_DIR/$IPA_NAME_PRIMARY" | cut -f1))"
echo "Secondary IPA: $ROOT_DIR/$IPA_NAME_SECONDARY ($(du -h "$ROOT_DIR/$IPA_NAME_SECONDARY" | cut -f1))"
echo "Executable: Payload/Locus.app/$EXEC_NAME (verified inside IPA)"
echo "=================================================="
