#!/bin/bash
# Bootstrap for vo-gen: install stack, fetch job files, start the wrapper.
# Runs as ROOT via Azure Run Command. No secrets needed (public temp repo).
set -u
RAW="https://raw.githubusercontent.com/Shivansh-MIshra-creates/vo-job-temp/main"
VO=/home/vo/vo
mkdir -p "$VO"
cd "$VO" || exit 1

echo "[bootstrap] downloading job files..."
for f in azure_run.py 06_FINAL_SCRIPT.txt quentin_reference_30s.wav vo_wrapper.sh; do
  curl -sL --retry 3 "$RAW/$f" -o "$f" || { echo "FAILED to download $f"; exit 1; }
done
chmod +x vo_wrapper.sh
ls -la

echo "[bootstrap] installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3-venv python3-pip ffmpeg git curl unzip > /tmp/apt.log 2>&1 || { tail -20 /tmp/apt.log; exit 1; }

echo "[bootstrap] creating venv + installing torch (CPU)..."
python3 -m venv /home/vo/venv
V=/home/vo/venv/bin
$V/pip install -q --upgrade pip
$V/pip install -q torch torchaudio --index-url https://download.pytorch.org/whl/cpu || exit 1
$V/pip install -q chatterbox-tts transformers==4.56.2 tokenizers librosa soundfile || exit 1

echo "[bootstrap] downloading chatterbox weights (~3GB)..."
mkdir -p weights
cd weights
for f in model.safetensors cond_enc.pt t3_cfg.safetensors; do
  curl -sL --retry 3 -o "$f" "https://huggingface.co/ResembleAI/chatterbox/resolve/main/$f" || { echo "FAILED weight $f"; exit 1; }
done
cd "$VO"
ls -la weights/

chown -R vo:vo /home/vo
echo "[bootstrap] starting wrapper as vo user..."
sudo -u vo nohup "$VO/vo_wrapper.sh" > "$VO/wrapper.log" 2>&1 &
disown
echo "BOOTSTRAP_DONE"
