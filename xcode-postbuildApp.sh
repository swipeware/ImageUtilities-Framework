#!/bin/bash
#
# Reset CFBundleVerion and CFBundleShortVersionString after build
CONFIG_FILE="${PROJECT_NAME}/Config/${PROJECT_NAME}Version.xcconfig"

/usr/bin/sed -i '' "s/\(CURRENT_PROJECT_VERSION = \).*/\1AUTOINCREMENT_FROM_GIT/" ${PROJECT_DIR}/${CONFIG_FILE}
/usr/bin/sed -i '' "s/\(MARKETING_VERSION = \).*/\1AUTOINCREMENT_FROM_GIT/" ${PROJECT_DIR}/${CONFIG_FILE}
/usr/bin/sed -i '' "s/\(DYLIB_CURRENT_VERSION = \).*/\1AUTOINCREMENT_FROM_GIT/" ${PROJECT_DIR}/${CONFIG_FILE}
