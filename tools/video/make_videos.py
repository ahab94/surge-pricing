#!/usr/bin/env python3
"""Builds the videos from recorded footage.

    bash tools/video/record_footage.sh            # raw gameplay -> build/footage/
    python3 tools/video/make_video_audio.py       # music + stingers -> build/video_audio/
    /usr/bin/python3 tools/video/make_videos.py [video-id ...]   -> build/videos/

Needs Pillow (captions, cards) and ffmpeg. Each video is a list of segments cut
from the footage (sped up a little: fast cuts read better), captions burned on
top, a title card and an end card. Audio = the music bed + comedy stingers
timed to the game's logged events. Adapted from the earlier games' video tools.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOOTAGE = os.path.join(ROOT, "build", "footage")
AUDIO = os.path.join(ROOT, "build", "video_audio")
OUT = os.path.join(ROOT, "build", "videos")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

PINK = (255, 79, 163)
SUN = (255, 210, 63)
GREEN = (87, 227, 107)
CREAM = (255, 248, 231)
INK = (42, 45, 54)


def font(size):
    return ImageFont.truetype(FONT, size)


def frame_size(orient):
    return (1080, 1920) if orient == "portrait" else (1920, 1080)


def centered(d, lines, cy, size, fill, W, stroke=10, gap=1.12):
    f = font(size)
    h = size * gap
    y = cy - h * len(lines) / 2
    for line in lines:
        w = d.textlength(line, font=f)
        d.text(((W - w) / 2, y), line, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
        y += h


def fit(d, lines, size, W, margin=90):
    while size > 40 and max(d.textlength(l, font=font(size)) for l in lines) > W - margin:
        size -= 4
    return size


def caption_png(path, text, style, orient):
    """A transparent full-frame PNG with the caption placed for the format."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n")
    portrait = orient == "portrait"
    if style == "big":       # punchline, mid-screen above the car
        size = fit(d, lines, 140 if portrait else 120, W)
        centered(d, lines, H * (0.36 if portrait else 0.30), size, SUN, W, stroke=14)
    elif style == "punch":   # big, but below the car, clear of the game's own popups
        size = fit(d, lines, 170 if portrait else 140, W)
        centered(d, lines, H * (0.66 if portrait else 0.72), size, (255, 77, 109), W, stroke=14)
    elif style in ("bubble_top", "bubble_bottom"):   # a big speech bubble over one half of a split screen
        size = fit(d, lines, 62, W, 200)
        f = font(size)
        bw = max(d.textlength(l, font=f) for l in lines) + 70
        bh = len(lines) * size * 1.15 + 40
        cy = H * (0.29 if style == "bubble_top" else 0.67)
        x0, y0 = (W - bw) / 2, cy - bh / 2
        d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], 30, fill=(255, 255, 255, 245), outline=INK, width=6)
        d.polygon([(W / 2 - 22, y0 + bh - 3), (W / 2 + 22, y0 + bh - 3), (W / 2, y0 + bh + 34)], fill=(255, 255, 255, 245))
        d.line([(W / 2 - 22, y0 + bh), (W / 2, y0 + bh + 34), (W / 2 + 22, y0 + bh)], fill=INK, width=6)
        centered(d, lines, cy, size, INK, W, stroke=0)
    elif style in ("tag_top", "tag_bottom"):   # name tag on one half of a split screen
        f = font(52)
        tw = d.textlength(text, font=f) + 60
        cy = H * (0.36 - 0.155 if style == "tag_top" else 0.74 - 0.155) + 40
        d.rounded_rectangle([40, cy - 40, 40 + tw, cy + 40], 26, fill=PINK + (240,), outline=INK, width=5)
        d.text((70, cy - 30), text, font=f, fill=(255, 255, 255))
    elif style == "hook_top":   # hook above a split screen
        size = fit(d, lines, 76, W, 120)
        f = font(size)
        bw = min(W - 40, max(d.textlength(l, font=f) for l in lines) + 80)
        bh = len(lines) * size * 1.15 + 46
        cy = H * 0.085
        d.rounded_rectangle([(W - bw) / 2, cy - bh / 2, (W + bw) / 2, cy + bh / 2], 34, fill=(255, 255, 255, 238))
        centered(d, lines, cy, size, INK, W, stroke=0)
    elif style == "hook":    # white box at the top (portrait: below the HUD clock)
        size = fit(d, lines, 74 if portrait else 70, W, 160)
        f = font(size)
        bw = min(W - 40, max(d.textlength(l, font=f) for l in lines) + 80)
        bh = len(lines) * size * 1.15 + 46
        cy = H * (0.17 if portrait else 0.2)
        d.rounded_rectangle([(W - bw) / 2, cy - bh / 2, (W + bw) / 2, cy + bh / 2], 34, fill=(255, 255, 255, 238))
        centered(d, lines, cy, size, INK, W, stroke=0)
    else:                    # "low": lower-third label
        size = fit(d, lines, 72 if portrait else 64, W, 160)
        f = font(size)
        bw = max(d.textlength(l, font=f) for l in lines) + 80
        bh = len(lines) * size * 1.15 + 40
        y0 = H * (0.70 if portrait else 0.78) - bh / 2
        d.rounded_rectangle([(W - bw) / 2, y0, (W + bw) / 2, y0 + bh], 28, fill=(20, 22, 28, 200))
        centered(d, lines, y0 + bh / 2, size, CREAM, W, stroke=0)
    img.save(path)


def star(d, cx, cy, r, fill):
    import math
    pts = []
    for i in range(10):
        rad = r if i % 2 == 0 else r * 0.45
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    d.polygon(pts, fill=fill, outline=INK, width=6)


def review_png(path, orient, name, stars, quote):
    """A big phone-notification review: app name, stars, rider, the quote.
    `name` may start with "top:" or "bottom:" to sit over half of a split screen."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    where = "mid"
    if ":" in name and name.split(":")[0] in ("top", "bottom"):
        where, name = name.split(":", 1)
    portrait = orient == "portrait"
    cw = W - (90 if portrait else 700)
    fq = font(54 if portrait else 46)
    # Wrap the quote to the card width.
    words, lines, line = ('"' + quote + '"').split(), [], ""
    for w in words:
        t = (line + " " + w).strip()
        if d.textlength(t, font=fq) > cw - 80 and line:
            lines.append(line)
            line = w
        else:
            line = t
    lines.append(line)
    ch = 200 + len(lines) * 66
    cy = {"mid": H * (0.62 if portrait else 0.6), "top": H * 0.36, "bottom": H * 0.74}[where]
    x0, y0 = (W - cw) / 2, cy - ch / 2
    d.rounded_rectangle([x0 + 8, y0 + 12, x0 + cw + 8, y0 + ch + 12], 40, fill=(0, 0, 0, 90))
    d.rounded_rectangle([x0, y0, x0 + cw, y0 + ch], 40, fill=(255, 252, 244, 250), outline=INK, width=6)
    d.text((x0 + 40, y0 + 26), "YOINK", font=font(40), fill=PINK)
    d.text((x0 + 190, y0 + 34), "New review", font=font(32), fill=(120, 120, 130))
    for i in range(5):
        star(d, x0 + 70 + i * 82, y0 + 120, 34, SUN if i < stars else (205, 205, 205))
    d.text((x0 + 70 + 5 * 82, y0 + 92), name, font=font(48), fill=INK)
    y = y0 + 170
    for l in lines:
        d.text((x0 + 40, y), l, font=fq, fill=INK)
        y += 66
    img.save(path)


def card_png(path, orient, kind):
    """Title or end card: the game name in the app's pink, five stars, a line."""
    W, H = frame_size(orient)
    img = Image.new("RGB", (W, H), (32, 34, 42))
    d = ImageDraw.Draw(img)
    # A faint street grid behind everything.
    for x in range(0, W, 160):
        d.rectangle([x, 0, x + 50, H], fill=(40, 43, 53))
    for y in range(0, H, 160):
        d.rectangle([0, y, W, y + 50], fill=(40, 43, 53))
    portrait = orient == "portrait"
    title = ["SURGE", "PRICING"] if portrait else ["SURGE PRICING"]
    size = fit(d, title, 200 if portrait else 190, W)
    cy = H * 0.40
    centered(d, title, cy, size, PINK, W, stroke=16)
    sy = cy + size * len(title) * 0.62 + 40
    for i in range(5):
        star(d, W / 2 + (i - 2) * 110, sy, 44, SUN if i < 4 else (120, 120, 120))
    if kind == "intro":
        lines = ["Your driver rating", "is your health bar."] if portrait else ["Your driver rating is your health bar."]
        centered(d, lines, sy + 170, 70 if portrait else 66, CREAM, W, stroke=8)
    else:
        lines = ["Free in your browser.", "Coming soon."]
        centered(d, lines, sy + 190, 70, CREAM, W, stroke=8)
        centered(d, ["a game by ahab94"], H - (230 if portrait else 110), 44, (200, 200, 210), W, stroke=4)
    img.save(path)


# --- Videos ----------------------------------------------------------------
# segments: (footage clip, start s, end s, speed)
# captions: (start, end, text, style), times from the first gameplay frame
#           (after the title card), in *output* seconds
# sfx: (time, name, volume), same clock

VIDEOS = []   # filled in by specs.py next to this file, from each clip's .events

sys.path.insert(0, os.path.dirname(__file__))
from specs import VIDEOS  # noqa: E402,F811


# --- Assembly --------------------------------------------------------------

def run(cmd):
    subprocess.run(cmd, check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def clip_scale(clip):
    try:
        with open(os.path.join(FOOTAGE, clip + ".scale")) as f:
            return float(f.read().strip())
    except OSError:
        return 1.0


def cut(src, start, end, speed, path, W, H):
    """Cut [start, end] (game seconds) from a clip. "a|b" stacks two landscape
    clips into one portrait frame: the split-screen comparison format."""
    clips = src.split("|")
    k = clip_scale(clips[0])
    a, b = start / k, end / k
    cmd = ["ffmpeg", "-loglevel", "error", "-y"]
    for c in clips:
        cmd += ["-ss", f"{a:.3f}", "-to", f"{b:.3f}", "-i", os.path.join(FOOTAGE, c + ".mp4")]
    if len(clips) == 1:
        cmd += ["-vf", f"setpts=PTS/{speed},scale={W}:{H},fps=60"]
    else:
        h = W * 9 // 16
        cmd += ["-filter_complex",
                f"color=c=0x20222a:s={W}x{H}:r=60:d={(b - a) / speed:.3f}[bg];"
                f"[0:v]setpts=PTS/{speed},scale={W}:{h},fps=60[t];[1:v]setpts=PTS/{speed},scale={W}:{h},fps=60[u];"
                f"[bg][t]overlay=0:{int(H * 0.36 - h / 2)}:shortest=1[x];[x][u]overlay=0:{int(H * 0.74 - h / 2)}:shortest=1"]
    cmd += ["-an", "-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p", path]
    run(cmd)


def still(png, seconds, path):
    run(["ffmpeg", "-loglevel", "error", "-y", "-loop", "1", "-t", str(seconds), "-i", png,
         "-vf", "fps=60,format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "16", path])


def loudness(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = err[err.rfind("Integrated loudness"):]
    return float(summary.split("I:")[1].split()[0])


def build(v, tmp):
    W, H = frame_size(v["orient"])
    parts = []
    intro = v.get("intro", 0)
    if intro:
        png = os.path.join(tmp, "intro.png")
        card_png(png, v["orient"], "intro")
        parts.append(os.path.join(tmp, "intro.mp4"))
        still(png, intro, parts[-1])
    cut_times = []
    t = intro
    for i, seg in enumerate(v["segments"]):
        src, a, b, speed = seg[:4]
        hold = seg[4] if len(seg) > 4 else 0.0
        parts.append(os.path.join(tmp, f"seg{i}.mp4"))
        cut(src, a, b, speed, parts[-1], W, H)
        if hold:
            # Freeze the last frame so a review card can be read.
            held = parts[-1].replace(".mp4", "_h.mp4")
            run(["ffmpeg", "-loglevel", "error", "-y", "-i", parts[-1], "-vf",
                 f"tpad=stop_mode=clone:stop_duration={hold}", "-c:v", "libx264", "-preset", "fast",
                 "-crf", "16", "-pix_fmt", "yuv420p", held])
            parts[-1] = held
        t += (b - a) / clip_scale(src.split("|")[0]) / speed + hold
        cut_times.append(t)
    outro = v.get("outro", 0)
    if outro:
        png = os.path.join(tmp, "outro.png")
        card_png(png, v["orient"], "outro")
        parts.append(os.path.join(tmp, "outro.mp4"))
        still(png, outro, parts[-1])
    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    total = duration(joined)

    inputs, filters, last = [], [], "[0:v]"
    overlays = [(t0, t1, ("cap", text, style)) for t0, t1, text, style in v["captions"]]
    overlays += [(t0, t1, ("card", name, stars, quote)) for t0, t1, name, stars, quote in v.get("cards", [])]
    for i, (t0, t1, what) in enumerate(overlays):
        png = os.path.join(tmp, f"cap{i}.png")
        if what[0] == "cap":
            caption_png(png, what[1], what[2], v["orient"])
        else:
            review_png(png, v["orient"], what[1], what[2], what[3])
        inputs += ["-loop", "1", "-t", f"{total:.2f}", "-i", png]
        filters.append(f"{last}[{i + 1}:v]overlay=0:0:enable='between(t,{t0 + intro:.2f},{t1 + intro:.2f})'[v{i}]")
        last = f"[v{i}]"
    base = len(overlays) + 1

    cues = [(t + intro, n, vol) for t, n, vol in v.get("sfx", [])]
    cues += [(t0 + intro, "pop", 0.4) for t0, _, _, _ in v["captions"]]
    cues += [(c[0] + intro, "notify", 0.9) for c in v.get("cards", [])]
    cues += [(c - 0.15, "whoosh", 0.45) for c in cut_times[:-1]]
    if intro:
        cues.append((0.1, "notify", 0.8))
    audio_in = ["-stream_loop", "-1", "-i", os.path.join(AUDIO, "gig_groove.wav")]
    mix = [f"[{base}:a]volume={v.get('music_volume', 0.55)}[m]"]
    labels = ["[m]"]
    for j, (t, name, vol) in enumerate(cues):
        audio_in += ["-i", os.path.join(AUDIO, name + ".wav")]
        ms = max(0, int(t * 1000))
        mix.append(f"[{base + 1 + j}:a]adelay={ms}|{ms},volume={vol:.2f}[s{j}]")
        labels.append(f"[s{j}]")
    mix.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,atrim=0:{total:.2f},"
               f"loudnorm=I=-14:TP=-1.5:LRA=11,afade=t=in:d=0.2,afade=t=out:st={total - 1.0:.2f}:d=1.0,"
               f"aresample=48000[a]")
    graph = ";".join(filters + mix)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, v["id"] + ".mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", joined, *inputs, *audio_in,
         "-filter_complex", graph, "-map", last, "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "60",
         "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.2f}", out])
    # One-pass loudnorm lands within a dB or two; measure and nudge to -14 LUFS.
    gain = -14.0 - loudness(out)
    if abs(gain) > 0.3:
        fixed = out + ".tmp.mp4"
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", out, "-c:v", "copy",
             "-af", f"volume={gain:.2f}dB,alimiter=limit=0.89", "-c:a", "aac", "-b:a", "192k", fixed])
        os.replace(fixed, out)
    print(f"{v['id']}: {total:.1f}s, {loudness(out):.1f} LUFS -> {os.path.relpath(out, ROOT)}")


def main():
    want = set(sys.argv[1:])
    for v in VIDEOS:
        if want and v["id"] not in want:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            build(v, tmp)


if __name__ == "__main__":
    main()
