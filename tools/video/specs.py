"""Edit decisions for each video. Times come from the footage's .events files
(build/footage/*.events), written by the game's --log-events while recording,
so every caption and stinger lands on the exact jump, splash or review.

Captions and sound cues are written in *source* time of a segment (`src`) and
converted to output time here, so re-cutting a segment doesn't break them.
"""


import os

FOOTAGE = os.path.join(os.path.dirname(__file__), "..", "..", "build", "footage")


def scale(clip):
    """Game-seconds per video-second for a clip (recorded with --speed)."""
    try:
        with open(os.path.join(FOOTAGE, clip + ".scale")) as f:
            return float(f.read().strip())
    except OSError:
        return 1.0


def video(vid, orient, segments, cues, intro=0.0, outro=0.0, music_volume=0.55, split=False, reviews=()):
    """cues: (segment index, source start, source end or None, kind, text-or-sound, extra)
    kind "cap": caption (extra = style); kind "sfx": sound (extra = volume)."""
    starts = []
    t = 0.0
    for seg in segments:
        clip, a, b, speed = seg[:4]
        starts.append(t)
        t += (b - a) / scale(clip.split("|")[0]) / speed + (seg[4] if len(seg) > 4 else 0.0)

    def out(seg, src_t):
        clip, a, _, speed = segments[seg][:4]
        return starts[seg] + (src_t - a) / scale(clip.split("|")[0]) / speed

    captions, sfx = [], []
    for seg, s0, s1, kind, what, extra in cues:
        if kind == "cap":
            captions.append((out(seg, s0), out(seg, s1), what, extra))
        else:
            sfx.append((out(seg, s0), what, extra))
    # reviews: (segment, game time, seconds on screen, name, stars, quote) shown
    # as a big phone-notification card (split screen: name may be "top"/"bottom").
    cards = [(out(seg, t0), out(seg, t0) + secs, name, stars, quote) for seg, t0, secs, name, stars, quote in reviews]
    return {"id": vid, "orient": orient, "segments": segments, "captions": captions, "sfx": sfx,
            "intro": intro, "outro": outro, "music_volume": music_volume, "split": split, "cards": cards}


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

    # "Same ride. Two passengers." The identical reckless drive, Nana on top,
    # a Livestreamer below. Their bubbles fire at the same instants.
    video("short-same-ride", "portrait",
          segments=[("l-same-nana|l-same-streamer", 11.7, 32.0, 1.0, 3.0)],
          cues=[
              (0, 11.7, 15.0, "cap", "Same ride.\nTwo passengers.", "hook_top"),
              (0, 11.7, 32.0, "cap", "NANA", "tag_top"),
              (0, 11.7, 32.0, "cap", "LIVESTREAMER", "tag_bottom"),
              (0, 12.22, 14.9, "cap", "Nice and slow now, dear.", "bubble_top"),
              (0, 12.22, 14.9, "cap", "Yo chat, we're in a rideshare!", "bubble_bottom"),
              (0, 15.25, 17.6, "cap", "I'm calling your mother.", "bubble_top"),
              (0, 15.25, 17.6, "cap", "CLIP IT!", "bubble_bottom"),
              (0, 15.25, None, "sfx", "bonk", 0.7),
              (0, 17.90, 20.6, "cap", "MY HIP!", "bubble_top"),
              (0, 17.90, 20.6, "cap", "CHAT SAW THAT!", "bubble_bottom"),
              (0, 17.90, None, "sfx", "bonk", 0.7),
              (0, 20.87, 24.3, "cap", "My dentures!", "bubble_top"),
              (0, 20.87, 24.3, "cap", "AGAIN! AGAIN!", "bubble_bottom"),
              (0, 20.87, None, "sfx", "bonk", 0.7),
              (0, 24.55, 27.0, "cap", "MY HIP!", "bubble_top"),
              (0, 24.55, 27.0, "cap", "CHAT SAW THAT!", "bubble_bottom"),
              (0, 24.55, None, "sfx", "bonk", 0.7),
              (0, 27.21, 30.0, "cap", "I'm calling your mother.", "bubble_top"),
              (0, 27.21, 30.0, "cap", "AGAIN! AGAIN!", "bubble_bottom"),
              (0, 30.6, None, "sfx", "sad_trombone", 0.6),
          ],
          reviews=[(0, 30.3, 5.5, "top:Grandpa Walt", 1, "My hip has filed a complaint."),
                   (0, 30.3, 5.5, "bottom:xXBlazeXx", 5, "SUBSCRIBE TO THIS DRIVER")],
          outro=2.5),

    # "I drove Nana like an action movie." Four rides, four 1-star reviews, deactivated.
    video("short-nana-action", "portrait",
          segments=[
              ("p-nana-action", 4.6, 13.9, 1.0, 2.2),
              ("p-nana-action", 21.0, 30.4, 1.0, 2.2),
              ("p-nana-action", 38.9, 44.7, 1.0),
              ("p-nana-action", 59.6, 71.0, 1.0),
          ],
          cues=[
              (0, 4.6, 8.0, "cap", "I drove Nana like\nan ACTION MOVIE", "hook"),
              (1, 21.0, 22.6, "cap", "Ride #2", "low"),
              (2, 38.9, 40.4, "cap", "Ride #3", "low"),
              (3, 59.6, 61.1, "cap", "Ride #4", "low"),
              (3, 67.9, None, "sfx", "record_scratch", 0.7),
              (3, 68.4, None, "sfx", "sad_trombone", 0.8),
          ],
          reviews=[(0, 13.65, 2.9, "Nana Rose", 1, "I have seen the other side, young man."),
                   (1, 30.25, 2.9, "Grandpa Walt", 1, "My hip has filed a complaint.")],
          outro=2.5),

    # "This passenger reviews you like a LinkedIn post."
    video("short-hustler", "portrait",
          segments=[
              ("p-hustler", 2.6, 24.0, 1.0, 2.6),
              ("p-hustler", 36.6, 41.5, 1.0, 2.8),
          ],
          cues=[
              (0, 2.6, 6.0, "cap", "This passenger reviews you\nlike a LinkedIn post", "hook"),
              (0, 5.26, None, "sfx", "bonk", 0.6),
              (0, 7.47, None, "sfx", "bonk", 0.6),
              (1, 36.6, 38.2, "cap", "Next Hustle Bro:", "low"),
          ],
          reviews=[(0, 15.65, 3.2, "Jaxon.eth", 1, "Time is money. You cost me both."),
                   (0, 23.9, 3.0, "Chad from Sales", 4, "Moves fast. Breaks things. Respect."),
                   (1, 41.4, 3.0, "Tyson, Founder", 1, "Slower than our quarterly growth.")],
          outro=2.5),

    # Livestreamers: the jump, the splash, the walk-out.
    video("short-streamer", "portrait",
          segments=[
              ("p-streamer", 8.9, 14.4, 1.0, 2.6),
              ("p-streamer", 66.6, 71.0, 1.0),
              ("p-streamer", 85.4, 87.2, 1.0, 2.8),
          ],
          cues=[
              (0, 8.9, 11.6, "cap", "Livestreamers rate\nyour driving differently", "hook"),
              (0, 11.0, None, "sfx", "slide_up", 0.7),
              (0, 11.89, None, "sfx", "boing", 0.7),
              (1, 66.6, 68.2, "cap", "One ride later...", "low"),
              (1, 69.12, None, "sfx", "splash", 1.0),
              (2, 85.4, 86.9, "cap", "...and then a boring ride.", "low"),
              (2, 87.2, None, "sfx", "record_scratch", 0.7),
          ],
          reviews=[(0, 14.35, 3.0, "ChadCam", 5, "Best content of my career. 5 stars + follow."),
                   (2, 87.15, 3.0, "TotallyNotBot", 1, "Ending stream. Walking.")],
          outro=2.5),
]
