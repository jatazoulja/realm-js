#!/bin/bash
rm -rf node_modules/realm node_modules/realm-tests
npm install realm realm-tests
cp ../../src/object-store/parser/queryTests.json node_modules/realm-tests/query-tests.json
/opt/android-sdk-linux/platform-tools/adb reverse tcp:8081 tcp:8081
/opt/android-sdk-linux/platform-tools/adb forward tcp:8082 tcp:8082
react-native run-android