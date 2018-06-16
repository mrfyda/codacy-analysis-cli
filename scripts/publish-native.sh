#!/usr/bin/env bash

#
# Simple Wrapper to deploy a native binary.
#
# Linux binaries can be built with `-t docker`
# but MacOS binaries require you to setup GraalVM.
#
# Setup GraalVM:
#   * Install GraalVM (https://www.graalvm.org/docs/getting-started/).
#   * Install JVMCI JDK (http://www.oracle.com/technetwork/oracle-labs/program-languages/downloads/index.html).
#   * Add GraalVM native-image bin to the beginning of your PATH.
#   * Set JVMCI JDK as your JAVA_HOME, JDK_HOME and JRE_HOME.
#   * Add JVMCI JDK bin to the beginning of your PATH.
#
# Example:
# ./scripts/publish-native.sh -t native -n codacy-analysis-cli -m com.codacy.analysis.cli.Main -s 2.12 1.0.0
#

set -e

SCALA_VERSION="2.12"
VERSION="1.0.0-$(git symbolic-ref --short HEAD)-SNAPSHOT"
TARGET="native"
OS_TARGET="$(uname | awk '{print tolower($0)}')"

function usage() {
  echo >&2 "Usage: $0 -n <app-name> -m <main-class> [-t target (native)] [-s scala-version (2.12)] [app-version (1.0.0-<branch-name>-SNAPSHOT)]"
}

while getopts :s:t:n:m:h opt
do
  case "$opt" in
    t)
      TARGET="$OPTARG"

      if [[ "${TARGET}" == "docker" && "${OS_TARGET}" == "darwin" ]]
      then
        echo >&2 "Target docker can only build binaries for linux."
        OS_TARGET="linux"
      fi
      ;;
    n)
      APP_NAME="$OPTARG"
      ;;
    m)
      APP_MAIN_CLASS="$OPTARG"
      ;;
    s)
      SCALA_VERSION="$OPTARG"
      ;;
    h | ?)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
	esac
done

shift $((OPTIND-1))

if [ -z "$APP_NAME" ]; then
  echo >&2 "App name was not provided."
  usage
  exit 1
fi

if [ -z "$APP_MAIN_CLASS" ]; then
  echo >&2 "Main class was not provided."
  usage
  exit 1
fi

if [ -n "$1" ]; then
  VERSION="$1"
fi

function app_classpath() {
  echo $(cat /dev/null | sbt 'export runtime:fullClasspath' | tail -n 1)
}

function build_cmd() {
  local BINARY_NAME=$1
  local APP_MAIN_CLASS=$2
  local APP_CLASSPATH=$3
  local FLAGS="--static -O1"
  local NATIVE_IMAGE_FLAGS="-H:+ReportUnsupportedElementsAtRuntime"

  if [[ "${OS_TARGET}" == "darwin" ]]
  then
    FLAGS="-O1"
  fi

  echo 'native-image -cp '"${APP_CLASSPATH}"' '"${FLAGS}"' '"${NATIVE_IMAGE_FLAGS}"' -H:Name='"${BINARY_NAME}"' -H:Class='"${APP_MAIN_CLASS}"
}

echo "Publishing ${APP_NAME} binary version ${VERSION} for ${OS_TARGET}"
BINARY_NAME="${APP_NAME}-${OS_TARGET}-${VERSION}"
BUILD_CMD="$(build_cmd ${BINARY_NAME} "${APP_MAIN_CLASS}" "$(app_classpath)")"

echo "Going to run ${BUILD_CMD} ..."
case "$TARGET" in
  native)
    ${BUILD_CMD}
    ;;
  docker)
    docker run \
      --rm=true \
      -it \
      -e JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS}" \
      --user=root \
      --entrypoint=bash \
      -v $HOME/.ivy2:$HOME/.ivy2 \
      -v $PWD:$PWD \
      findepi/graalvm:1.0.0-rc2-all \
        -c 'cd /tmp && '"${BUILD_CMD}"' && mv '"$BINARY_NAME $PWD/$BINARY_NAME"
    ;;
  *)
    echo >&2 "Could not find command for target $TARGET"
    exit 1
    ;;
esac
