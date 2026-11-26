#!/bin/zsh
# Buduje Bilard.app (Swift + SceneKit/Metal), bez Xcode
set -e
cd "$(dirname "$0")"
APP=Bilard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Bilard" \
  BilliardPhysics.swift Textures.swift TextureFactory.swift TableBuilder.swift AudioEngine.swift GameStateManager.swift HUDView.swift \
  AimIndicator.swift CameraDirector.swift TVCamera.swift ReplayRecorder.swift ShotEvaluator.swift GameSceneController.swift ChalkRack.swift SaveGame.swift Intro.swift Settings.swift Personalize.swift MenuViews.swift Tournament.swift TournamentViews.swift MusicEngine.swift Emblems.swift ClothMenu.swift Confetti.swift Challenges.swift HDRSupport.swift HDRIBackground.swift SelfTest.swift Intro3D.swift Props.swift LogoData.swift Bake.swift PenSound.swift FilmSound.swift TMIntroView.swift TMIntroKit.swift main.swift \
  -framework Cocoa -framework SceneKit -framework SpriteKit -framework AVFoundation -framework SwiftUI -framework Metal -framework QuartzCore -framework ModelIO -framework MetalKit -framework MetalPerformanceShaders
cp Resources/Shaders.metal Resources/blueroot.svg Resources/author.jpg Resources/podpis_art.json Resources/podpis_sig.png Resources/podpis_logo.png Resources/podpis_time.png Resources/podpis_pen.json Resources/podpis_studio.png "$APP/Contents/Resources/"
[ -d Assets ] && cp -R Assets "$APP/Contents/Resources/"
if [ ! -f Resources/AppIcon.icns ] || [ Icon.swift -nt Resources/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset && mkdir -p build
  swift Icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Bilard</string>
  <key>CFBundleDisplayName</key><string>Bilard 8-Ball</string>
  <key>CFBundleIdentifier</key><string>pl.marchewka.bilard</string>
  <key>CFBundleExecutable</key><string>Bilard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.5</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.sports-games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Gotowe: $(pwd)/$APP"
