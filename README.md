# Flutter web: a script's `Image:view()` samples nothing in a GPU canvas

On Flutter web, a Luau script that samples an embedded image through `Image:view()` in a GPU canvas draws nothing, and every render pass that binds the view drops its draws. The same file draws correctly in the Rive CLI, which runs the same deferred replay natively. The public reproduction, captures and a suggested fix are included here. Thank you for taking a look.

Following the arrangement in [#665](https://github.com/rive-app/rive-flutter/issues/665), the suggested fix is offered on a copy of `rive_native 0.2.0-dev.4` verbatim from pub.dev: [branch](https://github.com/rydmike/rive_native/tree/fix-web-image-views-0.2.0-dev.4), [one-commit comparison](https://github.com/rydmike/rive_native/compare/main...fix-web-image-views-0.2.0-dev.4), [`.patch`](https://github.com/rydmike/rive_native/compare/main...fix-web-image-views-0.2.0-dev.4.patch). The same patch is included [locally](patch/fix-web-image-views.patch). A separate report on two dart2wasm interop failures uses the same copy: [rive_wasm_issue](https://github.com/rydmike/rive_wasm_issue).

## Issue form entries

The following subsections follow the upstream runtime issue form in order.

### Submission checklist

- [x] I have confirmed the issue is present in the latest version of the `rive` Flutter package
- [x] I have searched the documentation and forums and could not find an answer
- [x] I have searched existing issues and this is not a duplicate

### Description

`image_view.riv` draws one embedded 256 px image twice: the left square with `renderer:drawImage`, the right square in a GPU canvas whose fragment shader samples `image:view()` at mip level 0. On Flutter web the right square stays empty, with both dart2js and dart2wasm, and the console shows, right after `rive_native: deferred replay active (web W1 inline)`:

```text
rive ore replay: skip make wrapImageView '' id=6 gen=0 (unresolved dep, churn)
rive ore replay: bind group handle 7 dropped pass draws: bindGroup '' skipped, unresolved dependency
```

Expected: both squares show the same orange and teal checker, as they do in the Rive CLI 1.9.1 on macOS (Metal), whose log reports `deferred replay: inline`. The same scenes draw natively in our app on iOS and Android with the same runtime.

Actual, with `rive 0.15.0-dev.4` / `rive_native 0.2.0-dev.4`: the right square is empty on every frame. With the suggested fix it matches the left square under both compilers, and the console shows no replay messages.

Two things combine in the web deferred replay:

1. The Ore image resolver in `DeferredReplayer` returns a resident 2D image unprepped. On the web that is a context agnostic `WebGL2RenderImage`, which only `prep()` turns into the `RiveRenderImage` that the `wrapImageView` make casts to, so the cast always fails. Foreign images are already prepped.
2. The recorder reads an image's size from the encoded header (`DeferredFactory::decodeImage`), so a script sees `width > 0` on its first frame and records the view then. The replay decodes its own copy through the browser, asynchronously, so the first replay finds it still decoding. The wrap and the bind groups made on it are recorded once, so the skip is permanent, where a 2D draw or a paint asks again on the next frame.

Fixing the first alone is not enough: with only that change, a debug build showed the resident image at width 0 when the wrap was made, and the scene stayed blank.

### Reproduction steps / code

The standalone project, its Rive source, the signed file, scripts and captures are at https://github.com/rydmike/rive_web_image_view_issue.

1. Use Flutter 3.47.9 stable / Dart 3.13.7. From `repro/`, run `flutter pub get`.
2. Run `flutter build web --release`.
3. From the repository root, run `python3 tool/serve.py repro/build/web --port 8123`.
4. Open http://127.0.0.1:8123 in Chrome. The left square shows the checker, the right square stays empty, and the console shows the two lines above.
5. To see the fix, rebuild with `--dart-define=RIVE_NATIVE_WASM_HOST=https://cdn.jsdelivr.net/gh/rydmike/rive_native@0.2.0-dev.4-web-fixes.1/native/wasm/`, which loads a wasm built from the fix branch ([build notes](https://github.com/rydmike/rive_native/blob/0.2.0-dev.4-web-fixes.1/WEB_FIXES.md)).

The script, [`rive_project/image_view.luau`](rive_project/image_view.luau), makes the view once, as soon as the image reports a size, which is how a scene uses a file image in a GPU canvas:

```lua
if self.bind == nil then
    self.bind = GPUBindGroup.new({
        layout = layout,
        textures = { { slot = 0, view = image:view() } },
        samplers = { { slot = 1, sampler = sampler } },
    })
end
```

The shader, [`rive_project/image_view.wgsl`](rive_project/image_view.wgsl), draws one textured quad with `textureSampleLevel(picture, pictureSampler, i.uv, 0.0)`. Reading level 0 only keeps empty lower mip levels out of the picture.

### Upload your reproduction files / stack trace

Attach `repro.zip`, produced by running `sh tool/make-zip.sh` from a clean, committed checkout. The script writes the ZIP to the folder above this repository. It includes the README, the Flutter project, the Rive project, the signed file, the fix patch and the captures in `evidence/`.

### Source `.riv` / `.rev` file

Attach the same `repro.zip`. `repro/assets/image_view.riv` is the signed build of `rive_project/` (Rive CLI 1.9.1, `rive rive_project --publish`, SHA-256 `00b16fc3326b963944adb7f1b243b13ed0a04c99dc4430f21a8c9b38e48664ab`). It carries the free-plan watermark. The image is generated by `tool/make_image.py`. No `.rev` backup is included; the RML, Luau and WGSL sources are in `rive_project/`.

### Screenshots / video

No video. Attach [`evidence/published-js.png`](evidence/published-js.png) (right square empty) and [`evidence/fixed-js.png`](evidence/fixed-js.png) (both squares drawn). [`evidence/cli-macos-metal.png`](evidence/cli-macos-metal.png) is the Rive CLI's own frame. The complete console output is in `evidence/<case>.console.log`.

### Rive Flutter package version

Latest published prereleases: `rive 0.15.0-dev.4` / `rive_native 0.2.0-dev.4`, which load `@rive-app/flutter-native-wasm@48.0.0`. Versions checked against pub.dev on 2026-11-08; the fix is based on `rive_native 0.2.0-dev.4`. The latest stable pair (`rive 0.14.11` / `rive_native 0.1.11`) also leaves the right square empty but prints no replay messages; this report concerns the prerelease pair, which a file built by the Rive CLI 1.9 needs.

### Flutter version

```text
Flutter 3.47.9 • channel stable • https://github.com/flutter/flutter.git
Framework • revision c197ca5199 (10 days ago) • 2026-10-29 10:10:20 -0400
Engine • hash 9e025265bef30b838c0c1b68cad19decf97048f2 (revision 89c39edfdf) (11 days ago) • 2026-10-27 19:51:20.000Z
Tools • Dart 3.13.7 • DevTools 2.60.0
```

### Device

Desktop web, arm64 host; real headless Google Chrome 156.0.8078.81, controlled with puppeteer-core 25.15.0, software WebGL with `--enable-unsafe-swiftshader`. The right square is also empty in a regular, GPU-backed Chromium window.

### OS version

macOS 27.0.1, build 26A434, arm64.

### Additional context

`rive_native` does not offer a public repository for a pull request, so the suggested fix follows the packaging used in #665: a verbatim pub.dev baseline, one commit and a downloadable patch.

- [Verbatim baseline](https://github.com/rydmike/rive_native/tree/0.2.0-dev.4-verbatim)
- [Fix branch](https://github.com/rydmike/rive_native/tree/fix-web-image-views-0.2.0-dev.4)
- [Compare main...fix-web-image-views-0.2.0-dev.4](https://github.com/rydmike/rive_native/compare/main...fix-web-image-views-0.2.0-dev.4)
- [Download .patch](https://github.com/rydmike/rive_native/compare/main...fix-web-image-views-0.2.0-dev.4.patch)
- [Related: shaders not working on web, #657](https://github.com/rive-app/rive-flutter/issues/657)
- [Related: web image re-uploads on every draw, #652](https://github.com/rive-app/rive-flutter/issues/652)

The replayer half of the fix, `renderer/include/rive/renderer/cmd/deferred_replayer.hpp`, is in rive-runtime, where the same code is on `main` today; a pull request there for that half can follow if it helps. The WebGL half is in `rive_native`'s `native/platform/wasm/webgl_factory.cpp`.

## How to run the reproduction

For the four captured cases, set `FLUTTER_BIN` to the Flutter 3.47.9 `flutter` executable, `CHROME_PATH` to Chrome and `FIXED_WASM_HOST` to the fixed build's folder, then from this repository's root:

```sh
npm ci --prefix tool --ignore-scripts --no-audit --no-fund
python3 tool/run-matrix.py
```

It builds the app with dart2js and dart2wasm, once with rive_native's own wasm and once with `--dart-define=RIVE_NATIVE_WASM_HOST=$FIXED_WASM_HOST`, serves each build on loopback, and runs `tool/capture.mjs` in headless Chrome. The capture waits for the file to load and the image to decode, saves the console and a screenshot, and counts the checker's orange and teal pixels in each half of the page: the artboard is centred, so the left square lands in the left half and the right square in the right. Results go to `evidence/`, builds to the ignored `.work/`.

## Evidence matrix

All cases used Flutter 3.47.9 / Dart 3.13.7, release builds, and Chrome 156.0.8078.81 on macOS 27.0.1 arm64.

| rive_native wasm | dart2js | dart2wasm |
| --- | --- | --- |
| Published `flutter-native-wasm@48.0.0` | right square empty, 3 replay messages | right square empty, 3 replay messages |
| Built from the fix branch | both squares drawn, no replay messages | both squares drawn, no replay messages |

Checker pixels, left and right half: 55,696 and 0 with the published wasm; 55,696 and 54,740 with the fix (the GPU quad and the vector draw filter the same image slightly differently). See [matrix.json](evidence/matrix.json) and the per-case JSON, console and PNG captures.

## What the fix changes

`DeferredFrameSink` gains `prepOreImage`, which the Ore image resolver calls for both resident and foreign images and which defaults to `prepForeignImage`, so native sinks keep their behaviour. The WebGL sink answers it with `WebGL2RenderImage::prepForWrap`: an image that is still decoding gets a zero filled, mipmapped texture at its header size, and `setWebImage` uploads into that same texture when the decode lands. GL Ore views borrow the texture id, so the view and its bind groups pick up the image with no change to the replay. An image already decoded takes the existing `prep` path.

Like `prep`, the early texture belongs to one WebGL context; a second context asking for the image before its decode lands gets nothing until then, as before. The fix does not change how an image moves between contexts, which [#652](https://github.com/rive-app/rive-flutter/issues/652) may concern.

## Existing-issue search

The GitHub issue search API was queried on 2026-11-08 without a state filter, covering open and closed issues: `"Image:view"` (0), `gpuCanvas` (3), `"GPU canvas"` (2), `wrapImageView` (0), `"bind group"` (0), `scripting web` (2), `texture web` (10), `shader web` (4), `deferred` (8), `WebGL image` (1) and `3D web` (0). Counts overlap. Exact queries and results are in [issue-search.json](evidence/issue-search.json).

[#657](https://github.com/rive-app/rive-flutter/issues/657) reports GPU canvas shaders failing on Flutter web, most recently with `beginRenderPass: color[1].view omitted but the receiving canvas has no backing texture (zero-sized)`. That is a different failure: in this reproduction the canvas starts and draws once the image view resolves. [#652](https://github.com/rive-app/rive-flutter/issues/652) concerns repeated image uploads, not a missing view. Search cannot prove absence, so please point to any existing report this one duplicates.
