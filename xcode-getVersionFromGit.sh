#!/bin/bash
#
# Get version from git

# VERSION OFFSET may be needed in older projects where you need to consider previous version numbering
# Do not modify below. Set VERSION_OFFSET in your Xcode Pre-action build script
if [ -z "$VERSION_OFFSET" ]; then
    VERSION_OFFSET=0
fi

git=`sh /etc/profile; which git`
cd ${PROJECT_DIR}
commitCount=`"$git" rev-list --all --count`
projectVersionBuildNumber=$(($commitCount + ${VERSION_OFFSET}))
marketingVersionString=`"$git" describe --match '[0-9]*' --tags --abbrev=0`
