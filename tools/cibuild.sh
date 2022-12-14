#!/bin/bash
#
# Copyright (c) 2016 IMcPwn  - http://imcpwn.com
# BrowserBackdoor by IMcPwn.
# See the file 'LICENSE' for copying permission
#

set -e

echo "Entering server directory"
cd server
echo "Installing ruby dependencies"
bundle install
echo "Checking server/ ruby files' syntax"
for i in $(echo ./*.rb); do echo "$i"; ruby -c "$i"; done
echo "Checking server/lib/bbs ruby files' syntax"
for i in $(echo ./lib/*/*.rb); do echo "$i"; ruby -c "$i"; done
echo "Returning to root of project"
cd -
