# Prompting playbook

How we ask Ludo for voices, pictures, animation and film, and what every review so far has taught us.
Read it before writing a `tools/ludo/vNN_content.py`. The redo reads it too: when the owner rejects a take
with a note, `tools/ludo/notes.py` hands this file's sections to Claude along with the note, and Claude
rewrites the next take's text or prompt. So a rule written here steers every redo from then on.

## The loop

1. A generator writes a review batch (`review/<batch>/batch.json`), and the owner listens or looks in the
   review table (`python3 tools/review/review.py serve --open`).
2. They **accept** or **reject**, and often leave a **note**: "more pause between sentences", "the rifle
   snaps 180 degrees in one frame". The note chips in the table (`N`) give the common ones the same words
   every time, so they sort cleanly into themes.
3. **Redo rejected** reads each note:
   - For a voice line, the words stay (they are the subtitle). The note becomes direction in what the voice
     is asked to say: the manifest's `speak`, shown in the table as *spoken as*. The redo rolls **3 takes**,
     keeps the rejected one beside them, and the owner picks with `←`/`→` or `1`–`9` and presses `A`.
   - For a picture, animation or film, the note rewrites the prompt, unless the owner edited the prompt
     themselves (`E`), in which case their words win.
   - Claude writes the direction when the `claude` command is installed. Without it, plain rules apply the
     voice lessons below and append the note to a prompt.
4. **Lessons** (`W` in the table, or `python3 tools/review/review.py lessons`) sums up every batch: how
   often a first take is kept, by kind and by voice, and what the notes ask for. After a review round,
   refresh the block at the end of this file and fold any new pattern into the rules:
   `python3 tools/review/review.py lessons --write docs/PROMPTING.md`.

The goal is first takes that don't need a note. The measure is the first-take rate in the lessons block.

## Voices

The cloned-voice endpoint (`/audio/speech`) takes two things: the text and a voice sample. It has no
emotion or speed setting, so everything we can do happens in the text, plus rolling again. A take costs
1 credit, so rolling several and picking one is the cheapest fix there is.

**The rules** (measured: see the speech lab below)

1. **Pauses.** When two sentences need air between them, write an ellipsis: `Gone... Taken.` rather
   than `Gone. Taken.`. It is the only mark that adds pause on this model, about +0.1 s, longer in 75%
   of pairs. Dashes and blank lines do nothing. `<break time="…"/>` tags and `[pause]` are **read
   aloud**: never use them. "More pause between sentences" is the second most common note (13 so far).
2. **Falling ends can't be written.** No punctuation made an ending fall: the differences were 3–5×
   smaller than two takes of the same text. So keep the full stop, and never add `!` or a trailing
   `...` unless the character shouts; both raise the whole line's pitch. What works is rolling
   several takes and keeping the one that falls. A redo does that on its own when a note asks for a
   falling end: it measures its takes (`tools/ludo/voice_measure.py`), puts the best first and marks
   each chip ("falls 3.1 st"). "Downward inflection" is the third most common note (12).
3. **Stress.** `*stars*` and CAPITALS barely change the word, but they aren't read aloud and the
   game strips the stars from subtitles (`Lines.subtitle`), so they are harmless. To really stress a
   word, write the line so the word lands at the end of its clause ("They are exactly where I
   expected. Strike."), then roll takes.
4. **Keep the words.** A performance note never changes the words. Direction goes in `speak`; the
   words stay in `text` and in `lines.json`.
5. **Roll more than once.** New lines get 2 takes, redos get 3 (`--takes`). Voices keep about 68% of
   their first takes, and some far fewer (see Lessons). Two takes of one text differ more than any
   punctuation does.
6. **Clone from the voice sample, never from a take.** Cloning Ysolde from one of her accepted menacing
   takes kept her voice, but made the endings rise in 4 of 4 pairs.
7. **Don't touch the advisor's voice.** It is cloned, it is the owner's favourite, and 87% of its first
   takes are kept. Never replace it with a Ludo-designed voice.

**VoiceStudio (OmniVoice, local and free), first pass, 28 Sep 2026.** The owner: "genuinely much higher
quality both in performance and in the audio itself", and "the three takes each is gold". Cloned from
each voice's own accepted take, and measured against the Ludo take of the same line (84 takes):
- It kept every word: no take ran long or short for its words.
- Its endings fall more reliably. Varek's go from rising to falling (+0.8 → −1.9 st), and Hask's from
  level (+0.0 → −1.7). That's the downward inflection the notes kept asking for.
- It holds a voice's pitch: Quill's Ludo takes wander from 122 to 192 Hz, while his clones stay near his
  reference.
- Its text levers: `[laughter]`, `[sigh]`, `[surprise-oh]`, `[dissatisfaction-hnn]`, `[confirmation-en]`,
  and a voice designed from traits (`instruct`) plus a seed.

**VoiceStudio voice design (new voices from traits), round 1, 28 Sep 2026.** 18 identities, 3 per commander.
The owner's ears:
- **Kept:** Varek B (elderly, low, British: "great"), Imre C (female, elderly, low, British: "excellent"),
  Oren A and B ("both good"; wanted: A's higher pitch with B's delivery).
- **Rejected:**
  - Russian accent: it came out American (Varek A "sucks", Ysolde A).
  - `whisper`: it really whispers ("the most human", but not the part).
  - Hask and Quill: "boring and flat".
  - Junk: one identity per commander (Varek C, Ysolde B, Quill B, Oren C, Imre B).
- **Overall:** designed voices read flatter than Ludo's performances. Clones of our own takes (the first
  pass) did better than both.

What the numbers can and can't tell (`tools/voicestudio/vs_casting.py`):
- **Junk is detectable.** It swings its pitch 10–18 semitones, or sits outside its gender's range (a
  woman at 80 Hz). Whisper (VoiceStudio's `/transcribe`) hears it as nothing, or as its hallucination
  "Thanks for watching!". Roll several seeds and throw those out before anyone listens.
- **"Flat" isn't detectable.** The flat Hask voices spread their pitch 4.4–6.3 st, the same as Varek B
  (4.5) and Imre C (5.6). Performance comes from the script the voice card reads (write it in
  character: exclamations, `...`, `[laughter]`) and from several takes. Ears choose.

**The chosen voices, 28 Sep 2026:** Oren A, Varek B and Imre C (designed), Hask's own voice (cloned), and for
Quill and Ysolde both their own voice and the recast they kept (Quill E, Ysolde F), heard line by line in
`vs_lines`.
- **Quill's "tsk".** Nearly every take cloned from Quill's greeting opened with a short burst 16–21 dB under
  the line, then silence. It isn't in his reference. It rumbles at 60–120 Hz, under his voice (about 180 Hz),
  while a murmured "Hm." sits at his own pitch; that's how `vs_lines.py` tells them apart and cuts only the
  click. Whisper still hears "Hmm, that will cost me." after the cut.
- **Notes on one voice's take carry to the others.** The first pass's notes are about the words, so they
  steer those lines in every voice: "Deerly" for Ysolde's "Dearly", "...ME..." for her "kneels to *me*",
  "NOT" for Oren's "not supposed to happen".

**ElevenLabs v4, 30 Sep 2026.** The owner on the samples: "holy shit the voice lines are such an
upgrade". v4 now speaks the game:
- **The advisor** is a v4 clone of her own voice ("perfect").
- **Each commander** is a v4 designed voice, one of three cards from a description written by the cast
  table below (`tools/elevenlabs/el_samples.py`).
- **Sound effects:** Ludo's won across the board against ElevenLabs'.
- **The design filter** refused "barely twenty" for Oren; "a young man in his twenties" passed.

**The cast** (the notes, boiled down)

| voice | wants | keep away from |
|---|---|---|
| advisor | dry, measured, a satisfied close; a pause between sentences | monotone; a rising end on "Commander" |
| varek | stoic, final, downward; slow pauses; "Next." is a verdict | high pitch; rushed pacing |
| ysolde | menace, low and cold; stressed possessives (*my*) | anything bright |
| quill | a smug clerk: every phrase descending, emphasis on money words (in*TER*est) | rising ends; odd mid-line pauses |
| hask | salty, loud, a sailor's anger | polite |
| imre | confident, clipped, a calculating pause before the verdict | hesitation |
| oren | a cocky young noble, smarmy, "Mother" | a Disney-prince brightness (he was recast once for it) |

## Pictures, animation and film

What the notes on art, sheets and films have asked for, as rules:

1. **Leave room in the frame.** A figure or an effect needs margin on every side, and headroom for whatever
   rises: a raised musket, a flame, smoke. Notes so far: "Cuts out the sides", "the top of the animation is
   cutting off". For animation use a manual margin (`frame_size: -9`, see `docs/LUDO_CAPABILITIES.md`).
2. **Describe the whole motion, including how it ends.** Keyframed moves snap when a rotation over about 90°
   has no middle keyframe ("the rifle snaps 180 degrees in one frame"). Add the middle pose, and write the
   path: "the musket swings back up in a slow arc to the shoulder".
3. **Say what the hands hold, all the way through.** An empty hand invites the model to invent a prop ("draws
   a stick from behind him"). A reload starts with the ramrod at the muzzle.
4. **Name the expression and where the eyes go**, especially at the end of a clip. Otherwise faces go glassy.
   Notes so far: "smile warmly, knowingly towards the commander", "acknowledge the player at the end".
5. **Stage the outcome, not the struggle**, when the outcome is the point: the enemy flag already on the
   ground and trampled, prisoners marched out by gloating redcoats.
6. **Say it positively.** Generators often draw what "no X" mentions. Say what should be there.
7. **Music:** the period's own tunes (fife and drum, the airs soldiers marched to around 1775–1865). A melody on
   the fife instead of sung lyrics.
8. **The imperial theme is unflinching.** Flags, uniforms and war imagery are drawn as they were. Don't
   sanitize them.
9. **A face reacts in character, and comes home.** (v2.4, the reactions in `tools/ludo/v24_content.py`.)
   Animate the portrait itself, not a separate mood picture: one can stop matching its portrait (the
   Lioness's angry face still wears the coat of a portrait since re-rolled), and v1.2's "eyes blazing
   with victory" made eyes glow.
   Write the expression as an arc in the character's own manner (Varek's grim nod, Hask's belly laugh,
   Quill peering over his spectacles), say they speak a few words when the moment has a line, and end
   it with "then settles back exactly into the starting pose, looking at the viewer" (with
   `final_same`). A fall says where it ends and that it stays there. Keep the head and hat in the frame.

## What things cost

Medians from `assets/ludo_ledger.json`: a speech take 1 credit, an image or an edit 0.5, a sound effect 2,
music 3, a sprite animation or keyframe sheet about 4, a 3D model 3, an image-to-video 12, a video from
references about 17. Check the balance before a big run (`python3 tools/ludo/ludo.py --account`).

## The speech lab

v1.11, 27 Sep 2026: 228 clips of the advisor, Varek, Ysolde and Quill (228 credits). The script is
`tools/ludo/lab_speech.py`, the measurements `tools/ludo/voice_measure.py` (stdlib, about 0.3 s a
clip), and every clip is in the review batch `v111_lab`, for ears.

| question | variants | result |
|---|---|---|
| **Pause** between two sentences (longest silence mid-clip, 24 per variant) | `A. B.` / `A... B.` / `A — B.` / `A.⏎⏎B.` | period 0.33 s; **ellipsis 0.42 s** (+0.10, longer in 75% of pairs); dash +0.00; blank line +0.03 |
| Stronger pause marks | `A. ... B.` / `A...... B.` / `<break time="0.8s" />` / `[pause]` | no better than the ellipsis. The break tag and `[pause]` were **spoken** in 12/12 and 11/12 clips (+2.2 s and +0.6 s of sound) |
| **Falling end** (last 350 ms against the line, in semitones, 16 per variant) | ends `.` / `...` / `!` | −1.29 / −0.75 / −1.22. The spread between two takes is 1.6–2.8, so no lever. `...` and `!` raised the whole line by about 2 semitones |
| Stress (4 clips each, for ears) | plain / `*not*` / `NOT` / `_not_` | no measurable change in the word's level; none read aloud |
| Emotional sample | Ysolde cloned from her menacing accepted take | same voice, endings rose in 4 of 4 pairs |

The spread between two takes of one text (0.13–0.21 s of pause, 2 semitones of ending) is as big as
any mark's effect. That is why redos roll several takes and measure them.

## Lessons

<!-- lessons:begin -->
_Generated by `python3 tools/review/review.py lessons --write docs/PROMPTING.md` from 10 review batches (2026-09-27). Don't edit by hand._

| kind | decided | kept first take | redone, then kept | still rejected | rounds to keep |
|---|---|---|---|---|---|
| audio | 299 | 203 (68%) | 84 | 12 | 1.31 |
| image | 71 | 56 (79%) | 6 | 9 | 1.1 |
| video | 9 | 7 (78%) | 1 | 1 | 1.12 |

First takes kept, by voice (8+ decided): quill 40%, varek 50%, ysolde 60%, hask 63%, oren 67%, imre 67%, advisor 87%.

| theme | notes | fixed by a redo | still open | e.g. |
|---|---|---|---|---|
| More feeling (menace, anger, smugness, conviction...) | 18 | 16 | 2 | “Close, getting there with the emotions” |
| More pause between sentences | 13 | 12 | 1 | “Needs more pause/spacing between the sentences.” |
| Falling (downward) inflection | 12 | 12 | 0 | “Your call, commander ends with the voice inflecting up, should be inflecting down” |
| Praise | 8 | 0 | 0 | “This is perfect” |
| Just roll again | 5 | 4 | 1 | “Redo” |
| Stress a word | 4 | 4 | 0 | “Inflection is wrong - should be downwards for both sentences. *always* should be emphasize…” |
| Pacing or delivery | 4 | 4 | 0 | “Redo pacing is all off” |
| Cropped or out of frame | 4 | 1 | 3 | “Cuts out the sides” |
| Pitch too high | 2 | 2 | 0 | “First sentence is great, splendid ennounciation is too high pitched should trail downwards…” |
| Artifacts, noise or invented objects | 2 | 1 | 1 | “Clean up the noise” |
| Motion snaps or jumps | 2 | 1 | 1 | “This is very close, but the rifle snaps 180 degrees in one frame towards the end instead o…” |
| Expression or acting | 2 | 1 | 1 | “Very close, but let's have her smile warmly, knowingly towards the commander as if guiding…” |
| Cut off at the end | 1 | 1 | 0 | “Last few blips of 'regiments' is cut off” |
| Doesn't sound like the character | 1 | 1 | 0 | “This is actually a great line and delivery but isn't Oren's voice” |
| Staging: what the scene shows | 1 | 1 | 0 | “Close, but next time let's just have the enemy flag already on the ground and being trampl…” |
| Hard to read the details | 1 | 0 | 1 | “close, a little hard to read the details” |
| Period or melody (music) | 1 | 0 | 1 | “Good idea - let's match closer to the melodies soldiers were playing around the civil/revo…” |
<!-- lessons:end -->
