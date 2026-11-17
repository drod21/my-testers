#!/usr/bin/env bash
# Builds an APK that installs on an emulator, for any supported framework.
# Usage: bash scripts/build/android.sh <app dir> <framework|auto>
# Env (optional): BUILD_COMMAND + ARTIFACT (custom build or prebuilt app)
# Output: $GITHUB_WORKSPACE/app.apk. All tool output goes to results/build-android.log
set -uo pipefail
ROOT=${GITHUB_WORKSPACE:-$PWD}; mkdir -p "$ROOT/results"; LOG="$ROOT/results/build-android.log"
cd "$1" || exit 1
FW=$2; [ "$FW" = auto ] && FW=$(bash "$ROOT/scripts/build/detect.sh")
echo "Framework: $FW"
q() { "$@" >>"$LOG" 2>&1; }
fail() { echo "::error::Android build failed ($FW): see the encrypted build log"; exit 1; }
npm_install() { [ -f package.json ] && { q npm ci || q npm install; }; return 0; }
apk() { find "${1:-.}" -path "*build/outputs/apk/*$2*/*.apk" -not -name '*androidTest*' -not -name '*unaligned*' | head -1; }

if [ -n "${BUILD_COMMAND:-}" ]; then
  FW=custom; q bash -c "$BUILD_COMMAND" || fail; OUT=${ARTIFACT:?ARTIFACT (path of the .apk) is required with BUILD_COMMAND}
else case "$FW" in
  flutter)
    if ! command -v flutter >/dev/null; then
      q git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$RUNNER_TEMP/flutter"; export PATH="$RUNNER_TEMP/flutter/bin:$PATH"
    fi
    q flutter pub get && q flutter build apk --release --target-platform android-x64 || fail
    OUT=build/app/outputs/flutter-apk/app-release.apk ;;
  expo)
    npm_install; q env CI=1 npx expo prebuild --platform android --no-install || fail
    (cd android && q ./gradlew assembleRelease -PreactNativeArchitectures=x86_64 --build-cache) || fail; OUT=$(apk android release) ;;
  react-native)
    npm_install; (cd android && q ./gradlew assembleRelease -PreactNativeArchitectures=x86_64 --build-cache) || fail; OUT=$(apk android release) ;;
  capacitor)
    # Release APKs are unsigned in a fresh Capacitor project: the debug APK is self-contained
    npm_install; q npm run build --if-present; q npx cap sync android || fail
    (cd android && q ./gradlew assembleDebug --build-cache) || fail; OUT=$(apk android debug) ;;
  maui)
    TF=$(grep -ohE 'net[0-9.]+-android' ./*.csproj | head -1)
    q dotnet workload install maui-android && q dotnet publish -f "$TF" -c Release -p:AndroidPackageFormat=apk -o "$RUNNER_TEMP/maui" || fail
    OUT=$(find "$RUNNER_TEMP/maui" -name '*-Signed.apk' | head -1) ;;
  kmp|native)
    D=.; [ -x ./gradlew ] || D=android
    (cd "$D" && chmod +x gradlew && q ./gradlew assembleDebug --build-cache) || fail; OUT=$(apk "$D" debug) ;;
  *) echo "::error::Unknown framework $FW"; exit 1 ;;
esac; fi
[ -n "${OUT:-}" ] && [ -f "$OUT" ] || { echo "::error::No APK found after the $FW build"; exit 1; }
cp "$OUT" "$ROOT/app.apk"; echo "APK ready ($FW)"
