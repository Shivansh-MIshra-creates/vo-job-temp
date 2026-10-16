#!/usr/bin/env python3
"""Portable Chatterbox voiceover runner for Azure VM (or any Ubuntu box).
Self-contained: splits script into 5 parts at scene boundaries, generates
with the approved natural Quentin-clone settings, enhances (crisp+clear),
joins into voiceover_full_final.wav.

Usage:
  python3 azure_run.py --weights ./weights --ref ./quentin_reference_30s.wav \\
      --script ./06_FINAL_SCRIPT.txt --out ./voice_out

Requires: python3.11+, torch (CPU), chatterbox-tts, librosa, soundfile, ffmpeg.
"""
import argparse, os, re, subprocess, sys, time
from pathlib import Path

for k in ("no_proxy", "NO_PROXY"):
    os.environ.pop(k, None)

def normalize(text: str) -> str:
    text = re.sub(r"\[SCENE[^\]]*\]", "", text)
    text = text.replace("₹", " rupees ").replace("€", " euros ")
    text = re.sub(r"\$(\d)", r"\1 dollars ", text)
    text = text.replace("%", " percent ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()

def get_parts(script_path):
    raw = open(script_path).read()
    scenes = [s.strip() for s in re.split(r"\[SCENE[^\]]*\]", raw) if s.strip()]
    assert len(scenes) == 11, f"expected 11 scenes, got {len(scenes)}"
    groups = [(0, 2), (2, 4), (4, 7), (7, 9), (9, 11)]
    return [(f"part{i+1}", normalize("\n\n".join(scenes[a:b])))
            for i, (a, b) in enumerate(groups)]

ENHANCE_AF = ("highpass=f=70,equalizer=f=3000:t=q:w=1:g=3,highshelf=f=9000:g=4,"
              "acompressor=threshold=-18dB:ratio=3:attack=10:release=150:makeup=5dB,"
              "alimiter=limit=0.95,loudnorm=I=-16:TP=-1.5:LRA=11")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--script", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--exaggeration", type=float, default=0.5)
    ap.add_argument("--temperature", type=float, default=0.7)
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)

    from chatterbox.tts import ChatterboxTTS
    import torchaudio as ta

    print(f"[{time.strftime('%H:%M')}] loading model from {a.weights} ...", flush=True)
    model = ChatterboxTTS.from_local(Path(a.weights), device="cpu")
    print(f"[{time.strftime('%H:%M')}] model loaded", flush=True)

    parts = get_parts(a.script)
    enhanced = []
    for name, text in parts:
        tp = out / f"{name}.txt"; tp.write_text(text)
        wp = out / f"{name}.wav"
        print(f"[{time.strftime('%H:%M')}] generating {name} ({len(text.split())} words) ...", flush=True)
        t0 = time.time()
        wav = model.generate(text, audio_prompt_path=a.ref,
                             exaggeration=a.exaggeration, temperature=a.temperature)
        ta.save(str(wp), wav, model.sr)
        print(f"[{time.strftime('%H:%M')}] {name} done in {(time.time()-t0)/60:.1f} min", flush=True)
        ep = out / f"{name}_final.wav"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(wp), "-af", ENHANCE_AF,
                        "-ar", "48000", "-ac", "1", str(ep)], check=True)
        enhanced.append(str(ep))

    lst = out / "join.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in enhanced))
    final = out / "voiceover_full_final.wav"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", str(lst), "-c", "copy", str(final)], check=True)
    dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(final)],
                         capture_output=True, text=True).stdout.strip()
    print(f"[{time.strftime('%H:%M')}] DONE -> {final} ({float(dur)/60:.1f} min of audio)")

if __name__ == "__main__":
    main()
