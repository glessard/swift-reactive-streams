#!/bin/sh

manifest="XCTestManifests.swift"
testspath="${PROJECT_DIR}/../Tests"

testdirs="ReactiveStreamsTests"

for testdir in ${testdirs}
do
  manifestpath="${testspath}/${testdir}/${manifest}"
  if /bin/test ! -s "${manifestpath}"
  then
    # echo "$manifestpath does not exist"
    generate="yes"
  else
    newer=`/usr/bin/find "${testspath}/${testdir}" -newer "${manifestpath}"`
    if /bin/test "${newer}"
    then
      # echo "newer files than $manifestpath"
      generate="yes"
    fi
  fi
done

if /bin/test "${generate}"
then
  if /bin/test "${XCODE_VERSION_ACTUAL}" -ge "0930"
  then
    /usr/bin/find "${testspath}" -name "${manifest}" -exec rm -f {} \;
    echo "Regenerating test manifests"
    /usr/bin/swift test --generate-linuxmain
  else
    echo "This version of the toolchain does not support automatic generation of XCTestManifests files"
  fi
else
  echo "No need to regenerate test manifests"
fi
