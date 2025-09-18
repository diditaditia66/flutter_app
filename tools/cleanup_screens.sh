#!/usr/bin/env bash
set -euo pipefail

ROOT="lib/screens"
TS=$(date +%Y%m%d-%H%M%S)
ARCHIVE="$ROOT/_archive_$TS"
mkdir -p "$ARCHIVE"

# Screens yang SELALU dipertahankan
KEEP=(
  "predict_data_screen.dart"
  "upload_data_screen.dart"
  "retrain_screen.dart"
  "home_screen.dart"
)

echo ">> Mendeteksi referensi screens di $ROOT ..."
mapfile -t FILES < <(find "$ROOT" -maxdepth 1 -type f -name "*.dart" -printf "%f\n" | sort)

in_keep() {
  local needle="$1"
  for k in "${KEEP[@]}"; do
    [[ "$k" == "$needle" ]] && return 0
  done
  return 1
}

TO_MOVE=()

for f in "${FILES[@]}"; do
  [[ "$f" == _archive_* ]] && continue

  if in_keep "$f"; then
    echo "KEEP   : $f"
    continue
  fi

  # hitung referensi di seluruh lib/ (kecuali file itu sendiri)
  REF_COUNT=$(grep -R --exclude-dir="_archive_*" -n "$f" lib/ | grep -vE "/$f:" | wc -l || true)

  if [[ "$REF_COUNT" -eq 0 ]]; then
    echo "ARCHIVE: $f (tidak ada referensi)"
    TO_MOVE+=("$f")
  else
    echo "USED   : $f (referensi: $REF_COUNT)"
  fi
done

for f in "${TO_MOVE[@]}"; do
  mv "$ROOT/$f" "$ARCHIVE/$f"
done

echo
echo ">> Selesai. Dipindahkan ke: $ARCHIVE"
for f in "${TO_MOVE[@]}"; do
  echo "   - $f"
done
