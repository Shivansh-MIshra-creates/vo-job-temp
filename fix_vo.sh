#!/bin/bash
# fix_vo.sh — repair the broken venv and complete the voiceover setup.
# Run as ROOT via Azure Run Command. Idempotent: safe to re-run.
set -u
VO=/home/vo/vo
echo "[fix] removing broken venv..."
rm -rf /home/vo/venv
echo "[fix] creating fresh venv..."
python3 -m venv /home/vo/venv
V=/home/vo/venv/bin
$V/pip install -q --upgrade pip
$V/pip install -q numpy --retries 10 --timeout 120 || { echo "numpy FAILED"; exit 1; }
echo "[fix] installing torch (CPU)..."
$V/pip install -q torch torchaudio --index-url https://download.pytorch.org/whl/cpu --retries 10 --timeout 300 || \
  { echo "[fix] CPU index failed, trying default PyPI..."; $V/pip install -q torch torchaudio --retries 10 --timeout 300 || { echo "torch FAILED"; exit 1; }; }
$V/pip install -q chatterbox-tts transformers==4.56.2 tokenizers librosa soundfile --retries 10 --timeout 300 || { echo "deps FAILED"; exit 1; }
$V/python -c "import torch, chatterbox.tts; print('imports OK')" || { echo "IMPORT CHECK FAILED"; exit 1; }
echo "[fix] downloading weights (~3GB)..."
mkdir -p $VO/weights && cd $VO/weights
for f in model.safetensors cond_enc.pt t3_cfg.safetensors; do
  curl -sL --retry 5 --retry-all-errors -o "$f" "https://huggingface.co/ResembleAI/chatterbox/resolve/main/$f" || { echo "FAILED weight $f"; exit 1; }
done
cd $VO
chown -R vo:vo /home/vo
echo "[fix] starting wrapper..."
sudo -u vo nohup "$VO/vo_wrapper.sh" > "$VO/wrapper.log" 2>&1 &
disown
echo "FIX_DONE"
