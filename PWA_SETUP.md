PWA setup for Notimapa

Steps to prepare the web build for Netlify and make the app installable (PWA):

1. Icons
- Copy `assets/images/titulo_mapa.png` to `web/icons/` and create the following files (you can reuse the same image but correctly sized):
  - `web/icons/titulo-192.png` (192x192)
  - `web/icons/titulo-512.png` (512x512)
  - `web/icons/titulo-maskable-192.png` (192x192, maskable)
  - `web/icons/titulo-maskable-512.png` (512x512, maskable)

2. Manifest
- `web/manifest.json` references these icons and sets `display: standalone`. No further edits required unless you want different colors or name.

3. index.html
- The page already contains an install banner (beforeinstallprompt) which will show on mobile. Title and apple-touch-icon are set to use the `titulo` icons.

4. Build
- Run locally to verify:
  flutter clean
  flutter pub get
  flutter build web

- The output folder `build/web` is ready to be uploaded to Netlify.

5. Netlify
- Create a new site and drag/drop the contents of `build/web` or connect the repo and set build command `flutter build web` and publish directory `build/web`.

6. Service Worker
- Flutter's generated service worker is included in `build/web` by default. Test installability using Chrome DevTools > Application > Manifest and Service Workers.

Notes
- Make sure to clear cache and unregister previous service worker in the browser when testing new builds.
- If you want the full-screen splash screen to use the titulo image, consider adding platform-specific splash configuration when building for mobile.
