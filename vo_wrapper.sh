#!/bin/bash
# vo_wrapper.sh — runs as user 'vo' on the Azure VM.
# Runs azure_run.py, writes status.json for portal Run-Command checks.
# On success: converts to FLAC, uploads to file hosts, writes URLs to
# result_urls.txt, then IDLES (a watcher deallocates the VM after download).
# On failure: writes ERROR status and keeps the VM running for diagnosis.
set -u
VO=/home/vo/vo
OUT=$VO/voice_out
cd "$VO" || exit 1
export PATH=/home/vo/venv/bin:$PATH

set_status() { # $1=status $2=detail
  local part logtail
  part=$(grep -o 'generating part[0-9]' "$OUT/vo.log" 2>/dev/null | tail -1)
  [ -z "$part" ] && part="starting"
  logtail=$(tail -4 "$OUT/vo.log" 2>/dev/null | tr '\n' ';' | cut -c1-400)
  python3 - "$1" "$part" "$2" "$logtail" <<'EOF' > "$OUT/status.json"
import json, sys, time
print(json.dumps({"status": sys.argv[1], "ts": int(time.time()),
                  "part": sys.argv[2], "detail": sys.argv[3],
                  "log_tail": sys.argv[4]}))
EOF
}

upload_result() { # $1=file -> prints URL or empty
  local f="$1" url=""
  url=$(curl -s -m 120 -F "reqtype=fileupload" -F "fileToUpload=@$f" https://catbox.moe/user/api.php) && [[ "$url" == https://* ]] && { echo "$url"; return; }
  url=$(curl -s -m 120 -F file="@$f" https://tmpfiles.org/api/v1/upload | python3 -c "import sys,json;print(json.load(sys.stdin).get('data',{}).get('url',''))" 2>/dev/null) && [[ "$url" == https://* ]] && { echo "$url"; return; }
  url=$(curl -s -m 120 -F files[]="@$f" https://uguu.se/upload.php | python3 -c "import sys,json;print(json.load(sys.stdin).get('files',[{}])[0].get('url',''))" 2>/dev/null) && [[ "$url" == https://* ]] && { echo "$url"; return; }
  echo ""
}

mkdir -p "$OUT"
set_status "provisioned" "stack installed, starting generation"

echo "[wrapper] starting azure_run.py at $(date -u)"
set +e
python3 azure_run.py --weights ./weights --ref ./quentin_reference_30s.wav \
  --script ./06_FINAL_SCRIPT.txt --out "$OUT" > "$OUT/vo.log" 2>&1
RC=$?
set -u

FINAL="$OUT/voiceover_full_final.wav"
if [ $RC -eq 0 ] && [ -f "$FINAL" ] && [ "$(stat -c%s "$FINAL")" -gt 1000000 ]; then
  echo "[wrapper] generation OK, converting to FLAC..."
  ffmpeg -y -v error -i "$FINAL" -c:a flac "$OUT/voiceover_full_final.flac"
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FINAL")
  URL=$(upload_result "$OUT/voiceover_full_final.flac")
  {
    echo "duration_s=$DUR"
    echo "flac_bytes=$(stat -c%s "$OUT/voiceover_full_final.flac")"
    echo "url=$URL"
  } > "$OUT/result_urls.txt"
  set_status "done" "duration_s=$DUR url=$URL"
  echo "[wrapper] DONE. Result URL: $URL — idling for watcher."
else
  echo "[wrapper] FAILED rc=$RC"
  set_status "error" "rc=$RC"
  echo "[wrapper] VM left RUNNING for diagnosis."
fi
# idle so the watcher can fetch results / diagnose, then deallocate
sleep 86400
