# Ludo.ai: what else it can make for CONCURRENT

Written 27 Sep 2026. It covers every Ludo capability I could find, what each costs, and which ones matter for this game. I made 25 real generations (86.5 credits) to check the most promising ones. The samples are in the review batch `review/ludo_explore`. They are experiments, not game assets, and nothing in the game changed.

**Sources**

- The MCP server's own tool list: `tools/list` on `https://mcp.ludo.ai/mcp` (server `ludoai` 0.9.10, 36 tools). It lists every tool's parameters and price.
- The public REST spec: `https://api.ludo.ai/api-documentation/swagger.json`. It lists every path.
- Ludo's own docs, read with the free `getDocs` and `searchDocs` tools. The sections used: sprite-generator, video-generator, audio-generator, image-generator, 3d-generator and api-mcp.
- Ludo's changelog: [ludo.ai/whats-new](https://ludo.ai/whats-new).
- EO7's Ludo tooling (`tools/ludo_client.py`, `ludo_sprites.py`, `ludo_views.py`, `ludo_ui.py`, `docs/11-GENERATED-ASSETS.md`), for field experience with `editSpritesheet`, `generatePose` and `rotateSprite`.

## The short version

CONCURRENT uses 10 of Ludo's 26 generation tools, and it runs every animation on the cheap `forge` model. Since 21 Sep, Ludo's default animation model is **Hydra**. It generates a sound track with every animation and can lip-sync speech. Video, 3D, keyframe animation, motion transfer, sheet editing and audio remix are all available through the API and have never been used here.

The five biggest wins, ranked:

| # | Opportunity | What the sample showed | Estimated credits |
|---|---|---|---|
| 1 | **Keyframe animation** for the battle figures (`animateSpriteKeyframes`) | Stand → our exact aim pose → recoil → shoulder arms → stand, in one clean sheet on the first try. | ~40 for 8 moves (fire, kneel-fire, charge, cheer, fall, reload, cannon, cavalry), rerolls included |
| 2 | **Living paintings** for the title, victory and defeat screens (`createVideo`, with the first frame as the last frame, then `upscaleVideo`) | The war-room splash moves: flags stir, sunbeams and dust, ships on the swell, room tone. It ends on its first frame, so it loops. | ~9 per screen, ~30 for three with one reroll each |
| 3 | **Cutscenes that star our own cast in our own rooms** (`createVideoFromReferences`) | The advisor walks into the painted war room, plants a flag and says a line, with cannon and brass under it. The style held, and moderation let it through. | 12.5 per 5 s shot, ~100 for capital falls, elimination, victory, defeat and the intro with rerolls |
| 4 | **Portraits that really say their line** (Hydra `animateSprite`, `image_type: portrait`) | The advisor's mouth moves through a spoken sentence, and the mp3 comes back in the same call. Listen to it to judge the sync. | 12 per 4 s line. ~100 for the 8 characters' biggest lines, or ~72 for Hydra talk loops without speech |
| 5 | **Untinted smoke and blast sheets** (`sprite-vfx` image → animate) | A painted powder-smoke burst with a flash core that blooms and fades. It is a separate layer, so it no longer takes the army's tint. That tint is why the v1.4 firing loops were dropped. | ~4.5 each, ~30 for musket smoke, cannon blast, fort explosion, capital fire, fuse spark and dust |

The next best: **music remixes** that keep the menu theme but change the mood (3 each), **unit variants** that re-skin an existing sheet but keep its motion (~4 each), a **marching song** with sung lyrics (3), **three-quarter tabletop views** of the figures (0.5 each), and **3D tin soldiers** for the dice table (~3.5 each).

## Ground rules that apply to every new tool

- **Every call is a job.** It returns `{id, status}` at once, and you poll `GET /assets/jobs/{id}?wait=55`. `ludo.py`'s `run_job` already does this for every path. The account may queue 50 jobs, but only **two ran at a time** today, so a 20-job batch took about 12 minutes.
- **URLs die after 7 days.** The edit tools (`editSpritesheet`, `createSpriteAudio`, `editVideo`, `upscaleVideo`) accept only *your own* generations from the last 7 days. So a re-skin or a loop repair has to run right after its source is made, in the same pipeline. The ledger URLs of anything older than a week are already dead for these tools.
- **`request_id` is sticky.** The API returns the existing job for an id it has already seen, instead of generating again. That is good for resuming, but a retry after a failure or a changed prompt needs a new id. With `ludo.py`, that means bumping the asset's `v` (its ids are `concurrent-<id>-v<N>`). Every retry here used a new name.
- **Input frames must be under 1 megapixel** for animation. EO7 hit this, and the advisor portrait is 1024×983 (just over), so the portraits are sent downscaled.
- **Moderation.** Hydra and the video models are strict about violence and weapons. Ludo's own docs say to retry a Hydra refusal on Forge. Today, only the two Hydra *motion transfers* failed (each with a bare "AI server error"). Muskets, cannon fire and "their capital has fallen" all passed on video.
- **Legacy models** (`blitz`, `eagle`, `eagle-audio` and `tango`, legacy since 17 Sep) are scheduled for removal. `forge`, which `ludo.py` defaults to, is current and still the right choice for simple loops and tiling. For anything complex, use `hydra`.
- **Free tools you should use:**
  - `getAccount` shows the balance: **6,845 credits** available before this exploration, with a 1,000-credit monthly plan plus about 7,090 extra.
  - `searchDocs` and `getDocs` answer "how do I…" questions.
  - `listAnimationPresets` lists 641 motions.
  - `listGenerations` and `listApiJobs` show recent work. They are how the sheets from the last 7 days were found for editing.
  - `cancelApiJob` refunds a queued job.
  - `POST /assets/uploads` uploads big inputs by URL instead of base64 (REST only).
- **Godot plays only Ogg Theora video.** Every Ludo video is an H.264 mp4, so video needs `ffmpeg` (not installed on this Mac) to become `.ogv`. The other route is cutting frames into a flipbook. `AVAssetImageGenerator` can do that without ffmpeg; the scratch tool `frames.swift` used for the posters here is 20 lines.
- **Ledger gap.** `getAccount` reports 1,244.7 credits used this billing period. The ledger added up to 837.5 before this pass. Part of the gap is that `ludo.py` never records the `remove-background` call behind its 88 `cutout` assets (0.5 each). The rest is probably other use of the same account: web-app generations, or EO7 if it shares the key. I can't see either.

## Inventory

**Used?** means whether CONCURRENT's `ludo.py` calls the tool today. All paths are relative to `https://api.ludo.ai/api`. The MCP name is the same tool over `https://mcp.ludo.ai/mcp`, where the body is wrapped in `requestBody`.

### Images

| MCP tool | REST | What it makes | Key parameters | Cost | Used? |
|---|---|---|---|---|---|
| `createImage` | `POST /assets/image` | An image from text | `image_type` (22 types: art, asset, sprite, sprite-vfx, icon, item-icon, ui_asset, logo, portrait, card-art, splash, fixed/side/vertical-scrolling background, parallax_layer, texture, tile, both tiling sprites, screenshot, 3d, generic), `art_style` (33), `perspective`, `aspect_ratio`, `n` 1–8, `augment_prompt` | 0.5 per image | Yes (art, icon, portrait, fixed_background, ui_asset, sprite, card-art, texture) |
| `generateWithStyle` | `POST /assets/image/style` | A new image in the style of one reference | `style_image`, `prompt`, `image_type`, `n` 1–4 | 0.5 per image | Yes |
| `editImage` | `POST /assets/image/edit` | An existing image, changed | `image`, `prompt`, optional `reference_image`, `n` 1–4 | 0.5 per image | Yes (no reference image yet) |
| `removeBackground` | `POST /assets/image/remove-background` | A cutout | `crop`, `creative_edit` (false keeps the pixels exact) | 0.5 | Yes (not recorded in the ledger) |

Web-only, not in the API: mask edit and mask erase, and "Generate from References" with two images.

### Sprites and animation

| MCP tool | REST | What it makes | Key parameters | Cost | Used? |
|---|---|---|---|---|---|
| `animateSprite` | `POST /assets/sprite/animate` | A spritesheet from one frame plus a motion prompt, with an optional `final_image` | `model` hydra, forge or forge-pixel; `duration` (hydra 3–5 s, forge 1–5 s); `frames` 4–64; `frame_size` (−9 is true size); `loop`, `crop`, margins; `image_type` (12 animatable types); `gif`, `individual_frames`, `spritesheet_with_background` | hydra 3/s (9 minimum), forge 1.5/s (4 minimum) | **Yes, forge only** |
| `animateSpriteKeyframes` | `POST /assets/sprite/animate-keyframes` | A sheet through first, **middle** and last frames; the prompt is optional | as above, plus `middle_image`. Forge holds the middle frame exactly. | as above | No |
| `transferMotion` | `POST /assets/sprite/transfer-motion` | A sheet that copies a preset or a video's motion | `preset_id` + `perspective` (side, hero, isometric, tactical, top) + `direction` (8), or `video`; 36 frames at most | hydra 3/s (9 minimum), forge 2/s (4 minimum) | No |
| `listAnimationPresets` | `GET /assets/sprite/animation-presets` | 641 presets: march, long-gun idle, walk and run, rifle reload, salute, victory cheer, 8 deaths, 20 hit reactions… | none | free | No |
| `generatePose` | `POST /assets/sprite/pose` | The same character in a new pose, plus a suggested motion prompt | `pose` (20 named, or "Other" + `description`), `n` 1–4 | 0.5 each | No |
| `rotateSprite` | `POST /assets/sprite/rotate` | The same sprite from a new camera angle | `camera_rotation` in steps of 45°, `camera_elevation` 0/30/60, `n` | 0.5 each | No |
| `editSpritesheet` | `POST /assets/sprite/edit` | A generated sheet, edited (from the last 7 days only) | `edit_mode`: `prompt` (new look, same motion, up to 5 reference images), `outpaint` (zoom out when the figure clips the frame), `fix_loop` | prompt: model rate. outpaint or fix_loop: 1 per output second. | No |
| `createSpriteAudio` | `POST /assets/sprite/audio` | A sound effect timed to a sheet's video (from the last 7 days) | `spritesheet_video_url`, `prompt` | 3 | No |

Web-only: Generate Transition, Generate Before/After (the API can do both with `final_image` or `initial_image`), and the Animation Pack and Animation Sequence exports.

### Video

| MCP tool | REST | What it makes | Key parameters | Cost | Used? |
|---|---|---|---|---|---|
| `createVideo` | `POST /assets/video` | Image to video, **with a sound track**; an optional `final_image` makes a loop | `model` griffin (480p) or griffin-hd; `duration` 5–15 s | griffin 1.5/s (7.5 minimum), HD 2/s | No |
| `createVideoFromReferences` | `POST /assets/video/references` | A new shot that composes 1–5 reference images (cast, props, room), with dialogue and sound from the prompt | `images`, `aspect_ratio` (16:9, 21:9 …), `duration` 5–15 s | griffin 2.5/s (12.5 minimum), HD 4/s | No |
| `editVideo` | `POST /assets/video/edit` | Your own video, changed, keeping its motion and framing | `prompt`, up to 5 `images` | griffin-hd 2/s (10 minimum) | No |
| `upscaleVideo` | `POST /assets/video/upscale` | 2× resolution (the source must be under 960 px, so only griffin 480p qualifies) | `video` | 0.2/s | No |

### 3D

| MCP tool | REST | What it makes | Key parameters | Cost | Used? |
|---|---|---|---|---|---|
| `create3DModel` | `POST /assets/3d-model` | Image to a textured GLB, plus 4 snapshots | `target_num_faces` 1k–200k, `texture_size` 1024 or 2048, `texture_type` pbr, simple or none | 3 | No |
| `rigModel` | `POST /assets/3d-model/rig` | A skeleton and skin weights | `rig_type` (general, humanoid, game, humanoid_template, …), `joint_naming` (includes **godot**) | 1 | No |
| `animate3DModel` | `POST /assets/3d-model/animate` | Animation-only GLB clips from a text prompt, several variants, each with an mp4 preview | `num_variants` 1–8, `mode`, `loop` | 0.2 | No |
| `animate3DModelPreset` | `POST /assets/3d-model/animate-preset` | A preset retargeted to a humanoid rig | `preset_id` (needs `clip_url`), `in_place`, `crop_loop` | 0.2 | No. **No preset has a `clip_url` today, so it can't be used.** |

Web-only: text to 3D, re-texturing a mesh, and re-topology.

### Audio and voice

| MCP tool | REST | What it makes | Key parameters | Cost | Used? |
|---|---|---|---|---|---|
| `createSoundEffect` | `POST /audio/sound-effect` | A one-shot, or a loop | `duration` 0–10 s, `loop` | 2 | Yes |
| `createAmbiance` | `POST /audio/ambiance` | A looping bed | `duration` 0–10 s, `loop` (defaults to true) | 2 | Yes |
| `createMusic` | `POST /audio/music` | A track that loops seamlessly, instrumental unless you give it **`lyrics`** | `duration` 0 or 10–180 s | 3 | Yes (never with lyrics) |
| `createAudioTransform` | `POST /audio/transform` | A **remix** of an existing clip: same identity, new mood or instruments | `sample` (15 MB max), `modification_strength` 0–1 (0.4 subtle, 0.6 clear, 0.8 strong), `duration` | 3 | No |
| `createVoice` | `POST /audio/voice` | A designed voice speaking up to 200 characters | `voice_description`, `type` human or non-human | 1 | Yes |
| `createSpeech` | `POST /audio/speech` | Speech in a cloned voice, up to 1,000 characters | `sample` | 1 | Yes |
| `createSpeechPreset` | `POST /audio/speech-preset` | Speech in one of 14 catalog voices, with **`emotion`** and **`language`** | `voice_preset_id`, `emotion` (8), `language` (40) | 1 | No |

### Account, jobs and docs (all free)

`getAccount` (`GET /assets/account`), `listApiJobs` / `getApiJob` / `cancelApiJob` (`/assets/jobs`), `listGenerations` (`GET /assets/generations`), `getDocs` / `searchDocs` (`GET /docs`, `/docs/search`), `submitApiFeedback` (`POST /assets/feedback`), `validateApiKeyEndpoint`. REST only: `POST /assets/uploads`, the `GET /assets/{images,sprites,videos,audio,3d-models}/results` lookups by request id, and `DELETE /assets/cli-key`.

## What the samples showed

All 25 generations are in `review/ludo_explore/` (35 review items), and every call is in `assets/ludo_ledger.json` under an `explore_` id. To open them: `python3 tools/review/review.py serve --open`, then pick **ludo_explore**. Videos show as a poster frame plus their sound track, and the mp4 path is in the item's text.

| Sample | Tool and settings | Credits | Verdict |
|---|---|---|---|
| Advisor says "Commander, the enemy is massing at the river." | Hydra `animateSprite`, portrait, 4 s, 36 frames | 12 | **Works.** The mouth shapes change through the line, and the mp3 is included. The voice is Hydra's own, not our cloned advisor; there is no way to feed it our audio. The default auto margin made the face small in its cell, so use `frame_size: -9` with a manual margin in production. |
| Volley from three keyframes: stand, `soldier_aim_pad`, stand | forge `animateSpriteKeyframes`, 3 s, 25 frames | 4.1 | **Best result of the day.** It raises, lands on our exact aim pose, recoils and shoulders arms, on the same 1152×768 canvas as the existing sheets. There is a small baked muzzle flash on 2 frames even though the prompt didn't ask for one. |
| Powder smoke burst | `sprite-vfx` image (0.5), then forge animate (4) | 4.5 | **Works**, and it is untinted. The last frames grow into the cell edges, so give it a manual margin. |
| War room as a looping living painting | `createVideo` griffin 5 s, first frame = last frame | 7.5 | **Works.** Flags, sunbeams and ships move, and the last frame matches the first. The sound track is room tone. The result is 832×480. |
| Same clip, 2× | `upscaleVideo` | 1 | **Works**: 1664×960 with the sound kept. |
| Same clip at night, in a storm | `editVideo` griffin-hd | 10 | **Looks great**: lightning at the windows, candles and lanterns, same composition. But it came back 832×480 with **no audio track**, although the job said `has_audio: true`. Editing a still (0.5) and animating it (7.5) is cheaper. |
| Advisor plants a flag in the war room: "Their capital has fallen. The map is ours." | `createVideoFromReferences` griffin 5 s 16:9, with the splash and the advisor as references | 12.5 | **Works on the first try.** The cast and the room stay on-model, and the line, cannon and brass are in the sound track. |
| Existing volley re-skinned as a grenadier | `editSpritesheet` prompt on our own `soldier_volley` sheet | 3.9 | **Works:** bearskin caps, same motion. It ran at Hydra's rate and returned audio, although the source was a forge sheet. The smoke clips at the cell edge; `outpaint` is Ludo's fix for that. |
| Existing cavalry gallop, loop-repaired | `editSpritesheet` fix_loop | 1.6 | **Works mechanically, but it wasn't needed.** Measured with `tools/sheet_tool.gd check`: the original's seam is 10.6 against a median step of 11.9, so it was already clean. The fixed sheet's seam is 6.6 against a median of 9.7, but frame 1 now jumps by 24 px. Use it only on sheets that fail the seam check. |
| Tin soldier "Death (Backward)" preset | `transferMotion`, hydra | 0 (failed) | **Failed twice** with a 500 "AI server error": once on the padded canvas and once unpadded with margins. Nothing was charged. See the forge retry below. |
| Tin soldier "Death (Backward)" preset | `transferMotion`, forge | 7.7 | **Mostly works.** It is a real backward fall that ends flat on the ground, which the v1.2 fall never managed. But the figure turns toward the camera at the start, and one leg kicks up and smears mid-fall. The preset also changes the canvas to square 768 px cells instead of our 1152×768 pad. Keyframes to a posed fallen frame should be cleaner. |
| Soldier seen from 45°, 30° up | `rotateSprite`, n=2 | 1 | **Works.** A clean three-quarter tabletop view in the same white-tin finish. |
| Soldier re-posed to guard | `generatePose` | 0.5 + 1 | On the narrow 176 px crop, the result was cropped and faced front, which is unusable. On the padded 1152×768 canvas with "Other" and a side-view description, both variants came back in a good charge-bayonet crouch. **Always give it the padded canvas.** |
| Menu anthem as a lament | `createAudioTransform` 0.6, 60 s | 3 | Made the track; needs a listen. |
| Musket volley variant | `createAudioTransform` 0.4 | 3 | Made a 2.0 s variant of the 1.5 s original; needs a listen. |
| Cannon sound for our cannon_fire sheet | `createSpriteAudio` | 3 | Made a 2.5 s WAV timed to the sheet; needs a listen. |
| Marching song with sung lyrics | `createMusic` with `lyrics`, 60 s | 3 | Made the song (62.6 s); needs a listen. |
| Angry catalog voice | `createSpeechPreset` "Deep voice man", Angry | 1 | Made the line; needs a listen. |
| Parallax smoke layer | `createImage` parallax_layer | 0.5 | **Works.** A wide painted haze band on transparency that repeats left to right. |
| Title logo | `createImage` logo, n=2 | 1 | **Fails.** It misspelled the name both times ("CONUURNENT", "CONCURNENT"). The ornament around the words is good. |
| Painted tin soldier, then 3D | `createImage` asset (0.5), then `create3DModel` 20k faces, 1024 px PBR (3) | 3.5 | **Works.** A convincing painted miniature GLB, 3.2 MB. |
| Rigged and marching in 3D | `rigModel` humanoid_template with godot joint names (1), then `animate3DModel` (0.2) | 1.2 | **Weak.** The rig put an arm bone outside the body, because the arms are tight to the sides and the figure is fused to its base. The docs ask for an A-pose or T-pose. |
| Animated seamless sea texture | forge `animateSprite`, `image_type: texture` | 0 (failed) | **Rejected three ways** (loop, with a final frame, and JPEG without margins) with the same 400: "a blank keyframe has nothing to animate from." It looks like an API bug for the texture type. Scroll the sea in a shader instead. |

Total spent on this exploration: **86.5 credits** (charged jobs only; the failed and cancelled jobs were refunded).

## Why these matter for CONCURRENT

- **The battle figures are the weakest generated art, and keyframes fix exactly that.**
  - The v1.4 changelog says the generated firing loops were dropped. The smoke was baked into the figure, and the shot is drawn in code.
  - v1.2 says the generated fall flipped the figure upside down, so the topple is drawn in code too.
  - Keyframes pin the poses the game already owns (`soldier_stand_pad`, `soldier_aim_pad`, `soldier_kneel_aim_pad`). Ludo only draws the in-betweens.
  - Make a fallen pose with `generatePose` ("Other: lying on his back", on the padded canvas, 0.5). Then stand → fallen as keyframes gives a real fall.
  - Keep smoke and flash as the separate untinted `sprite-vfx` sheets from win #5.
- **The title, victory and defeat screens are stills.** A 5 s loop with first frame = last frame costs less than two animations. The painting doesn't change, it just breathes.
- **Cutscenes were out of reach until now.** From references, the existing portraits and paintings become the cast and the sets. Capital taken or lost, a commander eliminated, victory and defeat are the moments that would carry them.
- **Talking portraits.**
  - Today's talk loops are forge mouth-flaps that don't follow any line.
  - Hydra can lip-sync a line, but only in its own voice. So the honest options are:
    - (a) let Hydra voice a few cinematic lines, or
    - (b) regenerate the talk loops on Hydra for better mouth shapes, throw its audio away and keep our cloned voices.
- **Unit variants for free motion.** `editSpritesheet` prompt re-skins a sheet and keeps its motion: grenadiers, guards, colonial troops, per-faction headgear. The 7-day rule means the pipeline must generate the base and its variants in one run.
- **Music.** Remixes keep the menu theme recognisable in new moods, so the soundtrack becomes one family (a lament for defeat, tension for a besieged capital). A sung marching song is new; all 14 tracks are instrumental today.

## Not worth it (now)

- **The `logo` image type**, because the name gets misspelled. Set the title in a real font over a generated ornament.
- **`createSpeechPreset`.** Our designed and cloned voices are already better, and the catalog voices don't fit the cast.
- **`animate3DModelPreset`**, because no preset has a `clip_url` yet. **Rigging these figures** also rigs badly (arms at the sides, fused base).
- **`editVideo`** at 10 credits: no audio in the result, and still 480p. Edit the still, then animate it.
- **`fix_loop` on loops that already pass the seam check**: it can add drift. Run `tools/sheet_tool.gd check` first.
- **Animated textures through the API**: the texture type is rejected. The shader can scroll and warp `tex/sea.webp` for free.
- **`createSpriteAudio`** (3) when timing doesn't matter. `createSoundEffect` is 2, and Hydra animations include sound anyway.
- **Hydra motion transfer** for now (two 500s). Forge presets, or keyframes, instead.
- **The legacy models** (`eagle`, `blitz`, `tango`).

## Recommended next generations

Ranked by value per credit. The estimates include one reroll where results vary.

| # | Generation | Tool | Est. credits |
|---|---|---|---|
| 1 | Battle moves from keyframes: fire, kneel-fire, charge, cheer, reload, fall (with a `generatePose` fallen frame), cannon fire, cavalry charge | `generatePose` + `animateSpriteKeyframes` (forge) | ~40 |
| 2 | Untinted VFX sheets: musket smoke, cannon blast, fort explosion, capital fire, fuse spark, dust kick | `createImage sprite-vfx` + `animateSprite` (forge, manual margin) | ~30 |
| 3 | Living title, victory and defeat paintings, 2× upscaled, converted to `.ogv` (install ffmpeg first) | `createVideo` (final = first) + `upscaleVideo` | ~30 |
| 4 | Cutscenes: capital taken, capital lost, a commander eliminated, victory, defeat, intro | `createVideoFromReferences` griffin, 5–8 s | ~100 |
| 5 | Talk loops on Hydra for the advisor and 7 commanders (audio discarded), or Hydra-voiced hero lines | Hydra `animateSprite` portrait, true size | ~72–100 |
| 6 | Leitmotif remixes: defeat, besieged capital, late-game tension from menu, plan and battle | `createAudioTransform` 0.5–0.7 | ~25 |
| 7 | Unit variants of the infantry and cavalry sheets, made in the same run as their bases | `editSpritesheet` prompt | ~50–100 |
| 8 | A marching song for the victory screen or the credits (several takes) | `createMusic` + `lyrics` | ~15 |
| 9 | Three-quarter tabletop views of infantry, cavalry and cannon for the map pieces | `rotateSprite` / `generatePose` | ~5 |
| 10 | 3D painted pieces for the dice table (infantry, cavalry, cannon, flag) | `createImage asset` + `create3DModel` | ~15 |

That is about 400 credits for everything, or about 200 for rows 1–4.

## What `ludo.py` would need

- **New kinds:**
  - `keyframes`, with a `middle_file` input.
  - `transfer`, with `preset_id`, `perspective` and `direction`.
  - `sprite_edit` (`edit_mode` plus a source asset id, run in the same lane right after its source).
  - `video` and `video_refs` (result `url`), and `upscale`.
  - `model3d` (result `model_url` and `snapshots`).
  - `audio_transform`.
- **A `model` of `hydra`**, where the result's `audio_url` should be downloaded too.
- **`gif: true`** for review batches. The review tool shows GIFs.
- **Record every charged call**, cutouts included.
- **Call `getAccount`** before a big run.
- **Downscale inputs over 1 MP** before animating.

The exploration script is `explore.py` in this session's scratch folder. It is kept out of the repo on purpose, but its request bodies are recorded in each `review/ludo_explore/raw/*.json`, and those can be lifted into the manifest format.

## v1.9 production run

Run on 27 Sep 2026, working through the "Recommended next generations" list above. Everything was installed at its game path, and every asset is also in a review batch whose `target` is that path. The batches are `review/v19_dice`, `v19_battle`, `v19_fx`, `v19_video`, `v19_portraits`, `v19_music` and `v19_models`. Each batch has **Install accepted** and **Redo rejected** actions (see below).

**Credits.** `getAccount` showed 7,715.4 available before the run and 7,338.5 after, so the run cost **376.9 credits**. The billing period had just reset, and "used" went from 0 to 376.9. Failed jobs were not charged.

| Group | What | Credits |
|---|---|---|
| G1 dice table and Fortune | felt, rail_wood and brass textures; plaque; fortune_star and fortune_empty; 2 sfx; howto_fortune | 9.0 |
| G2 battle moves | 4 `generatePose` poses (fallen, cheer, reload, cavalry charge), plus 8 `animateSpriteKeyframes` sheets. 3 of the sheets were rerolled once. | ~49 |
| G3 VFX | 6 `sprite-vfx` stills and forge animations. Rerolls: cannon blast, musket smoke. Two approaches were dropped (see below). | ~42 |
| G4 living paintings | victory and defeat, 8 s each, `createVideo` with first frame = last frame, then `upscaleVideo`. The title loop reused the survey clip. | 27.2 |
| G5 cutscenes | 6 × `createVideoFromReferences`, 7 s, then upscale | 113.4 |
| G6 talk loops | 7 × Hydra `animateSprite`, portrait, 3 s, 36 frames | 61.0 |
| G7 remixes, G8 songs | 3 × `createAudioTransform`, 90 s; 3 × `createMusic` with lyrics | 18.0 |
| G9 unit variants | 7 × `editSpritesheet` prompt: grenadier volley, charge, idle and march; cuirassier charge, idle and gallop | 39.5 |
| G10 views, G11 3D | 3 × `rotateSprite` (n=2); 4 × (`createImage` asset + `create3DModel`) | 17.0 |

**What worked**

- **Keyframe moves.**
  - Volley, kneeling volley, reload, fall, cannon fire and cavalry charge are clean. The fall is a real backward fall that ends flat on the `generatePose` "lying on his back" frame, re-padded to the stand's scale. There is no flip.
  - `pack_anims.pack_sheet` adds `fps`.
  - `v19_content.py` also reads `shot` and `muzzle` (firing sheets) and `down` (the fall) off the frames with `sheet_tool.gd probe`.
- **Living paintings.** Both new loops end on their first frame. The packer also crossfades the last 0.5 s into the start, video and sound together, so the `.ogv` loops with no jump or click (wrap PSNR 34-38 dB, the same as an ordinary frame step).
- **Cutscenes.** All six passed moderation on the first try: a burning capital stormed with bayonets, a court fleeing by night, colours trampled and prisoners marched off, a burning map. The cast and rooms stayed on-model.
- **Hydra talk loops.** Real speaking mouth shapes, a blink and small nods. Hydra's audio was discarded. Cells match the downscaled portrait exactly.
- **Unit variants.** They re-skin the game's own `soldier_idle`, `soldier_march`, `cavalry_idle` and `cavalry_gallop` sheets. Those were two days old, inside the 7-day window, so a grenadier keeps its bearskin in every animation.
- **3D pieces.** Four painted-tin GLBs, each about 20k triangles. Godot imports them cleanly. Each is normalised to 1 unit and centred on the origin.
- **Textures.** Seamless. The painted lighting on the rail and brass is flattened in post by subtracting a wide blur taken on a 3×3 tiling, so they still wrap.

**What failed, and the lessons**

- **Keyframe cells are not our canvas.**
  - `animateSpriteKeyframes` with `frame_size: -9` returns cells 21-145 px wider, and up to 4 px taller, than the 1152×768 input, with the picture shifted inside them.
  - The side that grows varies. The fall came back 1297×770, shifted 123 px.
  - `normalize_canvas` lines up the frame that should equal a keyframe (the first or the last, whichever bbox matches better), refines the shift by alpha PSNR, and re-cuts every cell to 1152×768.
  - Plain `animateSprite` (-9), Hydra portraits and edits keep the input size.
- **Prompt wording matters more than the keyframes.**
  - "jolts back with one sharp recoil" made the soldier turn around for three frames.
  - A charge prompt made him *fire*, with a flash baked into 4 frames.
  - The cheer ignored its stand start frame twice. The reroll also shrank the figure to 73% by the end, so the first take was kept, fetched back with `listGenerations?type=spritesheet&request_id=...`, and given a frame `order`.
  - Say "stays in side view facing right" and "does not fire, no flash".
- **Hydra `editSpritesheet` and the grenadier.**
  - "grenadier of the Imperial Guard… fringed epaulettes… moustache" failed 4 out of 4 times with a bare 500 "AI server error" (not charged).
  - The survey's short wording ("a tall bearskin cap instead of the shako…") worked every time.
  - Edits also trim the clip (the loop default), for example 2 s to 1.46 s, with the same frame count.
- **VFX.**
  - Forge grows the cloud into a hidden crop box. `smoke_musket` clipped at a 0.25 margin; at 0.45/0.35 it stayed inside.
  - `cannon_blast` hits a box at x ≤ 660, y ≥ 152 from frame 16, so its json plays frames 0-15 only.
  - The first stills baked in a black cannon muzzle. Say "no cannon, no gun barrel".
  - **Dropped:** `outpaint` (it returned 24 tiny 264×178 cells, flash gone) and "grow from a small puff on a big canvas" (forge barely moved it).
  - What worked instead: the musket smoke's grow-in is drawn in post, as 3 frames of the first frame scaled 30%, 55% and 80% from the muzzle.
- **Audio levels.** Remixes came back anywhere from -14.5 to -26.6 LUFS. `post_music` levels each one to the track it stands in for (-18 to -19; songs -14) with a limiter.
- **Rate limit and network.**
  - About 35 jobs polling at once hit `429 Rate limit reached`. `ludo.py` now keeps retrying 429s, with backoff and jitter, instead of giving up after 5 tries. A running job must never be abandoned.
  - A dropped TLS record (`SSLV3_ALERT_BAD_RECORD_MAC`) killed one submit, so `OSError` is retried too.
  - Only ~2-3 jobs run at once. The run took about 50 minutes of Ludo time.
- **Ledger.** Re-rolls used to overwrite an asset's entry, losing what earlier takes cost. That is about 17 credits of this run, which is why the ledger sums to 360 against 376.9 billed. `record()` now keeps a `history` list, and cut-outs are summed into `credits`, with `calls` listing each charged call.
- **Godot headless.** `sheet_tool.gd check` runs started to hang intermittently near the end: idle in the main loop, not quitting, and not tied to one file (the same bytes checked fine elsewhere). Import and `compile_check` still finished.

**Tools**

- `ludo.py` has new kinds:
  - `keyframes`, `transfer`, `sprite_edit`, `pose`, `rotate`
  - `video`, `video_refs`, `upscale`
  - `model3d`, `audio_transform`
  - `music` with `lyrics`
  - `model: hydra` (the `_audio.mp3` is saved) and `gif: true`
- `ludo.py` also has `--jobs N` (an ordered pool) and `--account`. It downscales local animation inputs over 1 MP, and records every charged call.
- `pack_anims.py` has `pack_loop`, `pack_sheet` and the v1.9 sheet list. A master in `assets/raw/v19/loops/` wins over the old one of the same name.
- `prep_sfx.py` has `--out` and falls back to a WAV.
- `sheet_tool.gd` has `probe`.
- `tools/ludo/v19_content.py` holds every prompt, the processing and the review batches:
  - `--make G1 …` generates, processes, installs and writes the batch.
  - `--post` processes what is already generated.
  - `--install --batch-name X [--dry-run]` copies accepted takes and their sidecars, then imports.
  - `--regen --batch-name X [--dry-run] [--jobs N]` bumps the rejected chains, uses an edited text as the prompt, moves the old take to `old/`, and does not install.
