"""Edit decisions for each video. Times come from the footage's .events files
(build/footage/*.events), written by the game's --log-events while recording,
so every caption and stinger lands on the exact jump, splash or review.

Captions and sound cues are written in *source* time of a segment (`src`) and
converted to output time here, so re-cutting a segment doesn't break them.
"""


def video(vid, orient, segments, cues, intro=0.0, outro=0.0, music_volume=0.55):
    """cues: (segment index, source start, source end or None, kind, text-or-sound, extra)
    kind "cap": caption (extra = style); kind "sfx": sound (extra = volume)."""
    starts = []
    t = 0.0
    for _, a, b, speed in segments:
        starts.append(t)
        t += (b - a) / speed

    def out(seg, src_t):
        _, a, _, speed = segments[seg]
        return starts[seg] + (src_t - a) / speed

    captions, sfx = [], []
    for seg, s0, s1, kind, what, extra in cues:
        if kind == "cap":
            captions.append((out(seg, s0), out(seg, s1), what, extra))
        else:
            sfx.append((out(seg, s0), what, extra))
    return {"id": vid, "orient": orient, "segments": segments, "captions": captions, "sfx": sfx,
            "intro": intro, "outro": outro, "music_volume": music_volume}


VIDEOS = [
    # The trailer: landscape. Every segment at 1.0x: at 60 fps, fractional
    # speed-ups drop frames unevenly and the motion judders.
    video("trailer", "landscape",
          segments=[
              ("l-stunt", 4.3, 14.9, 1.0),    # pick up a streamer, canal jump, 5-star review
              ("l-stunt", 60.6, 64.6, 1.0),   # ...the next jump falls short
              ("l-surge", 4.5, 15.2, 1.0),    # surge zone, hustle bro, $77 drop-off
              ("l-chase", 18.6, 22.9, 1.0),   # citizen's arrest... then two cops bumped
              ("l-rain", 23.0, 33.0, 1.0),    # rain, Nana, a gentle 5-star ride
              ("l-vip", 9.9, 14.7, 1.0),     # the motorcade: four diplomatic incidents
          ],
          cues=[
              (0, 4.6, 8.2, "cap", "Pick up passengers.\nGet them there. Fast.", "low"),
              (0, 5.13, None, "sfx", "notify", 0.8),
              (0, 10.3, None, "sfx", "slide_up", 0.8),
              (0, 10.4, 11.8, "cap", "SEND IT", "big"),
              (0, 11.27, None, "sfx", "boing", 0.7),
              (0, 12.0, 14.9, "cap", "Livestreamers tip for chaos.", "low"),
              (0, 14.03, None, "sfx", "kaching", 0.9),
              (1, 61.8, None, "sfx", "slide_up", 0.6),
              (1, 62.35, None, "sfx", "splash", 1.0),
              (1, 62.6, 64.6, "cap", "...usually.", "big"),
              (1, 62.9, None, "sfx", "sad_trombone", 0.7),
              (2, 4.6, 9.5, "cap", "Surge zones pay DOUBLE.", "low"),
              (2, 9.8, 15.2, "cap", "Hustle Bros pay extra to go FAST.", "low"),
              (2, 14.45, None, "sfx", "kaching", 0.9),
              (3, 18.6, None, "sfx", "siren", 0.6),
              (3, 18.7, 21.0, "cap", "Police chase? Join in.", "low"),
              (3, 21.05, None, "sfx", "kaching", 0.9),
              (3, 21.28, None, "sfx", "bonk", 0.8),
              (3, 21.68, None, "sfx", "bonk", 0.8),
              (4, 23.2, 28.0, "cap", "Nana hates speed.", "low"),
              (4, 28.2, 33.0, "cap", "Your rating is your health bar.", "low"),
              (4, 32.32, None, "sfx", "kaching", 0.8),
              (5, 9.9, 11.5, "cap", "Don't touch the motorcade.", "low"),
              (5, 11.60, None, "sfx", "bonk", 0.8),
              (5, 12.55, None, "sfx", "bonk", 0.8),
              (5, 12.68, None, "sfx", "bonk", 0.8),
              (5, 13.12, None, "sfx", "bonk", 0.8),
              (5, 13.25, 14.7, "cap", "-$100", "punch"),
              (5, 13.4, None, "sfx", "sad_trombone", 0.7),
          ],
          intro=2.6, outro=3.5),

    # A Short: portrait, hook first, the jump, the splash, and the review.
    video("short-health-bar", "portrait",
          segments=[
              ("p-stunt", 4.5, 14.9, 1.0),
              ("p-stunt", 60.6, 64.6, 1.0),
              ("p-stunt", 80.2, 82.9, 1.0),
          ],
          cues=[
              (0, 4.5, 8.6, "cap", "I made a game where your\ndriver rating is your\nHEALTH BAR", "hook"),
              (0, 5.13, None, "sfx", "notify", 0.8),
              (0, 10.3, None, "sfx", "slide_up", 0.8),
              (0, 10.4, 11.9, "cap", "SEND IT", "big"),
              (0, 11.27, None, "sfx", "boing", 0.7),
              (0, 12.2, 14.9, "cap", "Livestreamers\nlove it", "hook"),
              (0, 14.03, None, "sfx", "kaching", 0.9),
              (1, 60.6, 62.2, "cap", "Next ride.\nSame jump.", "big"),
              (1, 61.8, None, "sfx", "slide_up", 0.6),
              (1, 62.35, None, "sfx", "splash", 1.0),
              (1, 62.9, None, "sfx", "sad_trombone", 0.7),
              (2, 80.2, 82.9, "cap", "1 star.", "punch"),
              (2, 80.65, None, "sfx", "record_scratch", 0.7),
          ],
          outro=3.0),

    # Special traffic: a citizen's arrest, the ambulance, the motorcade.
    # Same cut in both formats (the portrait and landscape runs are identical).
    *[video(vid, orient,
            segments=[
                (f"{o}-chase", 17.6, 22.9, 1.0),   # catch the getaway car... and bump two cops
                (f"{o}-amb", 2.5, 8.0, 1.0),       # everyone pulls over
                (f"{o}-vip", 9.3, 14.7, 1.0),      # four diplomatic incidents in half a second
            ],
            cues=[
                (0, 17.6, 20.6, "cap", "In my rideshare game\nyou can make a\nCITIZEN'S ARREST", "hook"),
                (0, 17.6, None, "sfx", "siren", 0.5),
                (0, 21.05, None, "sfx", "kaching", 0.9),
                (0, 21.28, None, "sfx", "bonk", 0.8),
                (0, 21.68, None, "sfx", "bonk", 0.8),
                (0, 21.6, 22.9, "cap", "...and two fines for\nbumping the cops.", "low"),
                (1, 2.5, 8.0, "cap", "Ambulance?\nEveryone pulls over.", "hook"),
                (1, 2.6, None, "sfx", "siren", 0.6),
                (2, 9.3, 11.5, "cap", "Rule #1: don't touch\nthe motorcade.", "hook"),
                (2, 11.60, None, "sfx", "bonk", 0.8),
                (2, 12.55, None, "sfx", "bonk", 0.8),
                (2, 12.68, None, "sfx", "bonk", 0.8),
                (2, 13.12, None, "sfx", "bonk", 0.8),
                (2, 13.25, 14.7, "cap", "-$100", "punch"),
                (2, 13.4, None, "sfx", "sad_trombone", 0.7),
            ],
            outro=3.0)
      for vid, orient, o in [("short-citizens-arrest", "portrait", "p"),
                             ("special-traffic", "landscape", "l")]],
]
