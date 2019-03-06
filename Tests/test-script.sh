#!/bin/bash
set -e

COMPILER_MAJOR_VERSION=`echo ${COMPILER_VERSION} | awk -F . '{print $1}'`
TEST_OPTIONS="-c release"

swift --version
if [[ "$TRAVIS_OS_NAME" == "linux" ]]
then
  swift test ${TEST_OPTIONS} 2> /dev/null
else
  swift test ${TEST_OPTIONS}
fi

if [[ "${COMPILER_MAJOR_VERSION}" = "4" ]]
then
  MINOR_VERSION=`echo ${COMPILER_VERSION} | awk -F . '{print $2}'`
  if [[ "${MINOR_VERSION}" = "2" ]]
  then
    VERSIONS="4"
  fi
elif [[ "${COMPILER_MAJOR_VERSION}" = "5" ]]
then
  VERSIONS="4.2 4"
fi

for LANGUAGE_VERSION in $VERSIONS
do
  echo "" # add a small visual separation
  echo "Testing in compatibility mode for Swift ${LANGUAGE_VERSION}"
  swift package reset
  rm -f Package.resolved
  if [[ "$TRAVIS_OS_NAME" == "linux" ]]
  then
    swift test ${TEST_OPTIONS} -Xswiftc -swift-version -Xswiftc ${LANGUAGE_VERSION} 2> /dev/null
  else
    swift test ${TEST_OPTIONS} -Xswiftc -swift-version -Xswiftc ${LANGUAGE_VERSION}
  fi
done
