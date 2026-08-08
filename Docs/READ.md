```
clear
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test --update-goldens   # AlayaTimeline only
flutter test
flutter run
```

```
rm ~/alaya-upload-keystore.jks

keytool -genkey -v -keystore ~/alaya-upload-keystore.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
  
echo 'android/key.properties' >> .gitignore
echo '*.jks' >> .gitignore
nano android/key.properties

[key.properties in app/]
storePassword=Shah@1001
keyPassword=Shah@1001
keyAlias=upload

# An absolute path. A relative one resolves against `android/app/`, which is rarely what anyone means.
storeFile=/home/mrunalnshah/alaya-upload-keystore.jks  
```

``` release
git add -A && git commit -m "Phase 9"
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/$(git rev-parse --short HEAD)
```