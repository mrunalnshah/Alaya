```
clear
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test --update-goldens   # AlayaTimeline only
flutter test
flutter build apk --release
flutter run --release
flutter run
```

``` add to en-arb
python3 - <<'EOF'
import json, collections
arb = json.load(open('lib/app/l10n/app_en.arb'), object_pairs_hook=collections.OrderedDict)
arb.update(json.load(open('patch.json'), object_pairs_hook=collections.OrderedDict))
json.dump(arb, open('lib/app/l10n/app_en.arb','w'), indent=2, ensure_ascii=False)
EOF

flutter gen-l10n
```


```
rm ~/alaya-upload-keystore.jks

keytool -genkey -v -keystore ~/alaya-upload-keystore.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

OR

keytool -genkey -v \
  -keystore ~/Apps/alaya-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
  
echo 'android/key.properties' >> .gitignore
echo '*.jks' >> .gitignore
nano android/key.properties

[key.properties in app/]
storePassword=Shah@1001
keyPassword=Shah@1001
keyAlias=upload
storeFile=/home/mrunalnshah/Apps/alaya-upload-keystore.jks

# An absolute path. A relative one resolves against `android/app/`, which is rarely what anyone means.
storeFile=/home/mrunalnshah/alaya-upload-keystore.jks  
```

``` release
git add -A && git commit -m "Phase 9"
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/$(git rev-parse --short HEAD)
```