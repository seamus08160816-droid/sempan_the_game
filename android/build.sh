#!/bin/bash
# 웹 버전을 감싼 안드로이드 APK를 Gradle 없이 SDK 도구만으로 만들어요.
# 사용법: android/build.sh [버전 이름] [버전 코드]
# 필요: Android SDK (platforms;android-35, build-tools;35.0.0), JDK 11+, python3 + fonttools
# 서명: SEMPAN_KEYSTORE / SEMPAN_KS_PASS / SEMPAN_KEY_ALIAS 를 주지 않으면 디버그 키로 서명해요.
set -euo pipefail

VERSION_NAME=${1:-1.0.0-beta.1}
VERSION_CODE=${2:-1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$SDK/build-tools/35.0.0
PLATFORM=$SDK/platforms/android-35/android.jar
OUT=$ROOT/android/build

KEYSTORE=${SEMPAN_KEYSTORE:-$HOME/.android/debug.keystore}
KS_PASS=${SEMPAN_KS_PASS:-android}
KEY_ALIAS=${SEMPAN_KEY_ALIAS:-androiddebugkey}
if [ ! -f "$KEYSTORE" ]; then
  mkdir -p "$(dirname "$KEYSTORE")"
  keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KS_PASS" -alias "$KEY_ALIAS" -keypass "$KS_PASS" \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

rm -rf "$OUT"
mkdir -p "$OUT/assets" "$OUT/gen" "$OUT/classes"

python3 "$ROOT/web/build.py"
cp "$ROOT/web/dist/sempan.html" "$OUT/assets/index.html"

"$BT/aapt2" compile --dir "$ROOT/android/res" -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$PLATFORM" \
  --manifest "$ROOT/android/AndroidManifest.xml" -A "$OUT/assets" --java "$OUT/gen" \
  --min-sdk-version 24 --target-sdk-version 34 \
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
  "$OUT/res.zip"

javac --release 11 -nowarn -classpath "$PLATFORM" -d "$OUT/classes" \
  $(find "$ROOT/android/src" "$OUT/gen" -name '*.java')
"$BT/d8" --release --min-api 24 --lib "$PLATFORM" --output "$OUT" $(find "$OUT/classes" -name '*.class')

cp "$OUT/base.apk" "$OUT/unsigned.apk"
(cd "$OUT" && zip -q unsigned.apk classes.dex)
"$BT/zipalign" -p -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" --ks-key-alias "$KEY_ALIAS" \
  --out "$OUT/sempan.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify "$OUT/sempan.apk"
echo "android/build/sempan.apk ($(du -h "$OUT/sempan.apk" | cut -f1))"
