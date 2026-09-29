**v1.13 reading the map @ 0b2fe07**
- works as intended? mostly yes. across 3 real rounds on the ring, crosses, half-arrows, sword plates, the crimson capital ring, the roster's +N and the fuller recap all showed up and matched what happened, and every check in the `v113` screenshot script passed. the voice queue and music ducking were not checked (no sound on the test machine).
- does it land? yes. the "Last round: …" line in the tooltip is the best thing in the build. "Varek's 8 never got there: Dad's column met them on the border" is exactly the story you want someone on the couch to get. the threat line ("Quill could bring up to 10 against it; you'll have 5") turns the groan into something you can plan around, which is the game's whole hook. what drags it down is density. on a 30-land map in round 2 nearly every land has a small threat number, crosses pile up where the fighting is, and pips and amber rings get lost under the region labels.
- call: keep, and trim it. the information is right. there's just too much of it on screen at once.
- ideas:
  - keep the threat as the worst case, but add a "likely" read based on what that rival actually did last round (like "Varek has hit from Vaneholt twice"), so reading opponents becomes a skill and not just math.
  - when you seal orders that strip a land your own threat line marks as in danger, show one "this is the walk-in" preview on that land, so the core mistake gets a warning before it happens and not just an explanation after.
  - before round 2 planning starts, zoom the camera briefly onto the round's biggest cross (the upset or the lost capital), so the map opens on the story and not on clutter.
- ui/ux:
  - round 2 planning map: the small threat numbers sit on almost every land, enemy lands included (about 20 on the ring). show them only on your border lands, or only when you hover.
  - tooltips: the "N ways in" line lists the region's entrances, so it's the same on every land in that region (Vanehead, Vanefell and Vane Tor all say the same thing) and reads like it's about the land you're hovering. move it to the region hover or label it with the region's name. the tooltip box is also big and covers the middle of the map, so push it away from the cursor, toward the edge.
  - crosses: one mark means three different fates (thrown back, fell back, lost a scramble). you can tell it failed, but not how, without hovering. use a different mark for each fate, like a back-chevron for a fall-back.

caveats: the test screen was 1280×800, smaller than the 1440×900 target, and rendering was in software, so performance and small clipping were not judged.
