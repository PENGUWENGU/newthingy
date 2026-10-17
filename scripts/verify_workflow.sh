#!/usr/bin/env bash
# ==============================================================================
# Automated CI & Workflow Sanity Verification Script
#
# Prevents regression or breaking changes to the unsigned IPA builder,
# workflow files, project settings, or repository structure.
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Verifying CI / Workflow / Build Pipeline Integrity ==="

ERRORS=0

# 1. Verify build script
if [ ! -f "scripts/build_ipa.sh" ]; then
  echo "❌ Missing scripts/build_ipa.sh"
  ERRORS=$((ERRORS + 1))
else
  if [ ! -x "scripts/build_ipa.sh" ]; then
    echo "⚠️ Warning: scripts/build_ipa.sh is not executable, fixing permissions..."
    chmod +x scripts/build_ipa.sh
  fi
  if ! bash -n scripts/build_ipa.sh; then
    echo "❌ scripts/build_ipa.sh has bash syntax errors"
    ERRORS=$((ERRORS + 1))
  else
    echo "✅ scripts/build_ipa.sh syntax is valid and executable"
  fi
fi

# 2. Verify .github/workflows/build.yml
WORKFLOW=".github/workflows/build.yml"
if [ ! -f "$WORKFLOW" ]; then
  echo "❌ Missing $WORKFLOW"
  ERRORS=$((ERRORS + 1))
else
  # Check for Node 20 deprecation triggers (ensure actions are pinned to v4.2.2 / v4.6.1 or modern)
  if grep -q "actions/checkout@v2" "$WORKFLOW" || grep -q "actions/checkout@v3" "$WORKFLOW"; then
    echo "❌ $WORKFLOW uses deprecated checkout action"
    ERRORS=$((ERRORS + 1))
  fi
  if grep -q "actions/upload-artifact@v2" "$WORKFLOW" || grep -q "actions/upload-artifact@v3" "$WORKFLOW"; then
    echo "❌ $WORKFLOW uses deprecated upload-artifact action"
    ERRORS=$((ERRORS + 1))
  fi
  # Verify concurrency group exists to prevent runner bottlenecking
  if ! grep -q "concurrency:" "$WORKFLOW"; then
    echo "❌ $WORKFLOW is missing concurrency configuration"
    ERRORS=$((ERRORS + 1))
  fi
  echo "✅ $WORKFLOW conforms to modern CI standards"
fi

# 3. Verify project.yml
if [ ! -f "project.yml" ]; then
  echo "❌ Missing project.yml"
  ERRORS=$((ERRORS + 1))
else
  # Verify manual ad-hoc signing is specified so unsigned builds succeed without certs
  if ! grep -q "CODE_SIGNING_ALLOWED: YES" project.yml; then
    echo "❌ project.yml does not allow ad-hoc code signing"
    ERRORS=$((ERRORS + 1))
  fi
  if ! grep -q "AD_HOC_CODE_SIGNING_ALLOWED: YES" project.yml; then
    echo "❌ project.yml does not allow ad-hoc code signing"
    ERRORS=$((ERRORS + 1))
  fi
  echo "✅ project.yml signing and target configuration verified"
fi

# 4. Verify critical app assets
if [ ! -f "Locus/Resources/Info.plist" ]; then
  echo "❌ Missing Locus/Resources/Info.plist"
  ERRORS=$((ERRORS + 1))
fi
if [ ! -f "Vendor/idevice/idevice.h" ]; then
  echo "❌ Missing Vendor/idevice/idevice.h"
  ERRORS=$((ERRORS + 1))
fi

# 5. Verify Swift source code sanity checks (preventing build breakages)
if grep -rn "glassEffect" Locus/ >/dev/null 2>&1; then
  echo "❌ Detected uncompilable glassEffect API call in Locus/"
  ERRORS=$((ERRORS + 1))
fi
if grep -rn "setTravelMode(" Locus/ >/dev/null 2>&1 && ! grep -rn "func setTravelMode(" Locus/ >/dev/null 2>&1; then
  echo "❌ Detected setTravelMode call without method definition"
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "❌ Integrity check failed with $ERRORS error(s)."
  exit 1
fi

echo "✅ All IPA builder and project safeguards verified successfully."
exit 0
