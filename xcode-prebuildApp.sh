#!/bin/bash
#
# Auto update CFBundleVersion and CFBundleShortVersionString from git.
CONFIG_FILE="${PROJECT_NAME}/Config/${PROJECT_NAME}Version.xcconfig"
. ${PROJECT_DIR}/xcode-getVersionFromGit.sh

/usr/bin/sed -i '' "s/\(CURRENT_PROJECT_VERSION = \).*/\1$projectVersionBuildNumber/" ${PROJECT_DIR}/${CONFIG_FILE}
/usr/bin/sed -i '' "s/\(MARKETING_VERSION = \).*/\1$marketingVersionString/" ${PROJECT_DIR}/${CONFIG_FILE}
/usr/bin/sed -i '' "s/\(DYLIB_CURRENT_VERSION = \).*/\1$marketingVersionString\.$projectVersionBuildNumber/" ${PROJECT_DIR}/${CONFIG_FILE}
