#!/bin/bash
# Archive Plainfeed and upload it to TestFlight.
#
# Requires, once:
#   TEAM_ID            your Apple Developer team id (Xcode > Settings > Accounts,
#                      or developer.apple.com > Membership)
# And for unattended upload, an App Store Connect API key:
#   ASC_KEY_ID         e.g. 2X9R4HXF34
#   ASC_ISSUER_ID      uuid from App Store Connect > Integrations
#   ASC_KEY_PATH       path to the AuthKey_<KEYID>.p8 you downloaded
#
# Without the ASC_* vars this still archives, then uploads using the Apple ID
# signed into Xcode (you may get a prompt).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?set TEAM_ID — see comment above}"

ARCHIVE="build/Plainfeed.xcarchive"
BUILD_NO="${BUILD_NO:-$(date +%Y%m%d%H%M)}"

# NOTE: archiving signs with "Apple Development" first and -exportArchive
# re-signs for the App Store. That development profile requires at least one
# registered device on the team, so your iPhone must have been connected to
# Xcode once before the first archive will succeed. Overriding
# CODE_SIGN_IDENTITY to work around this does NOT work — it conflicts with
# automatic signing and the build refuses outright.
echo "==> archiving (build $BUILD_NO)"
rm -rf "$ARCHIVE"
xcodebuild -project Plainfeed.xcodeproj -scheme Plainfeed \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NO" \
  -allowProvisioningUpdates \
  archive

echo "==> uploading to App Store Connect"
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH")
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  "${AUTH[@]}"

echo "==> uploaded. Processing takes ~5-15 min, then it appears in TestFlight."
echo "    Build number: $BUILD_NO"
