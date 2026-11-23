# Bilard 8-Ball (macOS, Apple Silicon) — Swift + SceneKit/Metal

## Szybkie uruchomienie (bez Xcode)
```bash
cd "Bilard" && ./build.sh && open Bilard.app
```

## Konfiguracja w Xcode (macOS App target)
1. File ▸ New ▸ Project ▸ macOS ▸ App (Interface: SwiftUI lub Storyboard, Language: Swift) – nazwa `Bilard`.
2. Usuń wygenerowane pliki `ContentView.swift` i `*App.swift`. Dodaj do targetu wszystkie pliki `.swift` z tego folderu
   (`main.swift` jest punktem wejścia, więc nie może istnieć drugi `@main`).
3. Dodaj do **Copy Bundle Resources**: `Resources/Shaders.metal`, `Resources/blueroot.svg`, `Resources/AppIcon.icns`.
   Uwaga: `Shaders.metal` zawiera fragmenty shaderów (shader modifiers) wczytywane w czasie działania jako tekst –
   w Xcode ustaw jego *Target Membership* tylko na „Copy Bundle Resources”, a nie „Compile Sources”.
4. Frameworki (Build Phases ▸ Link Binary): Cocoa, SceneKit, SpriteKit, AVFoundation, SwiftUI, Metal, QuartzCore.
5. Deployment Target: macOS 14.0+. Architektura: arm64. App Sandbox bez dodatkowych uprawnień
   (dźwięk jest syntezowany, gra nie używa mikrofonu ani plików użytkownika). `NSHighResolutionCapable` = YES.

## Sterowanie
- Mysz: przeciągnij – obrót celownika (Shift – precyzyjnie, Option – sama kamera), przeciągnięcie w pionie – kąt kamery,
  scroll / pinch – zoom, PPM w dół i puść – uderzenie.
- Spacja: przytrzymaj = siła, puść = uderzenie. ←/→ – precyzyjne celowanie, ↑/↓ – nachylenie kija.
- C – widok z góry (płynna animacja), w widoku z góry klik/przeciągnięcie ustawia kierunek.
- Okrąg „Rotacja bili” – punkt uderzenia (top/back/side spin). P – ustaw białą, T – kolor sukna, N – nowa gra, M – dźwięk.

## Pliki
`BilliardPhysics.swift` fizyka 480 Hz · `TableBuilder.swift` stół/bile/kij/światło · `Textures.swift` tekstury proceduralne ·
`GameStateManager.swift` zasady 8-Ball, model HUD, AI · `GameSceneController.swift` kamery, celowanie, pętla gry ·
`HUDView.swift` SwiftUI HUD · `AudioEngine.swift` dźwięk 3D · `Intro.swift` logo BLUEROOT · `Resources/Shaders.metal`.

Test bez okna: `BILARD_AUTOSTART=1 BILARD_AUTOPLAY=1 ./Bilard.app/Contents/MacOS/Bilard` (partia komputer vs komputer z logiem tur),
`BILARD_SHOT=plik.png BILARD_SHOT_AT=4` (zrzut sceny, `BILARD_TOP=1` – widok z góry).
