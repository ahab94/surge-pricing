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
    # The trailer: landscape, ~40 s.
    video("trailer", "landscape",
          segments=[
              ("l-stunt", 4.3, 14.6, 1.25),   # pick up a streamer, close call, canal jump, 5-star review
              ("l-stunt", 49.6, 53.4, 1.0),   # ...the next jump falls short
              ("l-surge", 2.0, 15.2, 1.35),   # surge zone, hustle bro, $77 drop-off
              ("l-rain", 21.6, 32.2, 1.3),    # rain, Nana, a gentle 5-star ride
              ("l-stunt", 71.6, 76.9, 1.0),   # splash, retry, splash again
          ],
          cues=[
              (0, 4.6, 8.2, "cap", "Pick up passengers.\nGet them there. Fast.", "low"),
              (0, 5.13, None, "sfx", "notify", 0.8),
              (0, 8.55, None, "sfx", "honk", 0.6),
              (0, 10.3, None, "sfx", "slide_up", 0.8),
              (0, 10.4, 11.8, "cap", "SEND IT", "big"),
              (0, 11.27, None, "sfx", "boing", 0.7),
              (0, 12.0, 14.6, "cap", "Livestreamers tip for chaos.", "low"),
              (0, 13.52, None, "sfx", "kaching", 0.9),
              (1, 50.95, None, "sfx", "splash", 1.0),
              (1, 51.2, 53.4, "cap", "...usually.", "big"),
              (1, 51.6, None, "sfx", "sad_trombone", 0.7),
              (2, 2.3, 8.0, "cap", "Surge zones pay DOUBLE.", "low"),
              (2, 4.12, None, "sfx", "honk", 0.5),
              (2, 9.0, 15.2, "cap", "Hustle Bros pay extra to go FAST.", "low"),
              (2, 14.45, None, "sfx", "kaching", 0.9),
              (3, 21.8, 27.5, "cap", "Nana hates speed.", "low"),
              (3, 27.8, 32.2, "cap", "Your rating is your health bar.", "low"),
              (3, 31.27, None, "sfx", "kaching", 0.8),
              (4, 71.8, 73.0, "cap", "One more try.", "big"),
              (4, 73.22, None, "sfx", "splash", 1.0),
              (4, 74.4, None, "sfx", "record_scratch", 0.7),
              (4, 74.4, 75.6, "cap", "Again?!", "big"),
              (4, 75.68, None, "sfx", "splash", 1.0),
              (4, 75.9, None, "sfx", "sad_trombone", 0.7),
              (4, 75.9, 76.9, "cap", "5 stars though.", "big"),
          ],
          intro=2.6, outro=3.5),

    # A Short: portrait, hook first, the jump, then the double splash.
    video("short-health-bar", "portrait",
          segments=[
              ("p-stunt", 4.5, 14.6, 1.3),
              ("p-stunt", 71.6, 76.9, 1.0),
          ],
          cues=[
              (0, 4.5, 8.6, "cap", "I made a game where your\ndriver rating is your\nHEALTH BAR", "hook"),
              (0, 5.13, None, "sfx", "notify", 0.8),
              (0, 8.55, None, "sfx", "honk", 0.6),
              (0, 10.3, None, "sfx", "slide_up", 0.8),
              (0, 10.4, 11.9, "cap", "SEND IT", "big"),
              (0, 11.27, None, "sfx", "boing", 0.7),
              (0, 12.2, 14.6, "cap", "Livestreamers\nlove it", "hook"),
              (0, 13.52, None, "sfx", "kaching", 0.9),
              (1, 71.6, 73.0, "cap", "Next ride.\nSame jump.", "big"),
              (1, 73.22, None, "sfx", "splash", 1.0),
              (1, 74.4, None, "sfx", "record_scratch", 0.7),
              (1, 74.4, 75.6, "cap", "AGAIN?!", "big"),
              (1, 75.68, None, "sfx", "splash", 1.0),
              (1, 75.9, None, "sfx", "sad_trombone", 0.7),
              (1, 75.9, 76.9, "cap", "...", "big"),
          ],
          outro=3.0),

    # Special traffic: a citizen's arrest, the ambulance, the motorcade.
    # Same cut in both formats (the portrait and landscape runs are identical).
    *[video(vid, orient,
            segments=[
                (f"{o}-chase", 12.6, 17.8, 1.0),   # catch the getaway car... and bump a cop
                (f"{o}-amb", 2.5, 8.0, 1.3),       # everyone pulls over
                (f"{o}-vip", 9.6, 14.2, 1.0),      # four diplomatic incidents in half a second
            ],
            cues=[
                (0, 12.6, 15.6, "cap", "In my rideshare game\nyou can make a\nCITIZEN'S ARREST", "hook"),
                (0, 12.6, None, "sfx", "siren", 0.5),
                (0, 15.9, None, "sfx", "bonk", 0.8),
                (0, 16.0, None, "sfx", "kaching", 0.9),
                (0, 16.3, 17.8, "cap", "...and a fine for\nbumping the cop.", "low"),
                (1, 2.5, 8.0, "cap", "Ambulance?\nEveryone pulls over.", "hook"),
                (1, 2.6, None, "sfx", "siren", 0.6),
                (2, 9.6, 12.0, "cap", "Rule #1: don't touch\nthe motorcade.", "hook"),
                (2, 12.13, None, "sfx", "bonk", 0.8),
                (2, 12.18, None, "sfx", "bonk", 0.8),
                (2, 12.38, None, "sfx", "bonk", 0.8),
                (2, 12.52, None, "sfx", "bonk", 0.8),
                (2, 12.6, 14.2, "cap", "-$100", "punch"),
                (2, 12.9, None, "sfx", "sad_trombone", 0.7),
            ],
            outro=3.0)
      for vid, orient, o in [("short-citizens-arrest", "portrait", "p"),
                             ("special-traffic", "landscape", "l")]],
]
