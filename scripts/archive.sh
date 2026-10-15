#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
xcodegen generate
task_build="/tmp/longshot-release-${UID}"
xcodebuild -project LongShot.xcodeproj -scheme LongShot \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$task_build" \
  -archivePath "$task_build/LongShot.xcarchive" \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive \
  -archivePath "$task_build/LongShot.xcarchive" \
  -exportPath "$task_root/artifacts/AppStore" \
  -exportOptionsPlist "$task_root/ExportOptions.plist" \
  -allowProvisioningUpdates
