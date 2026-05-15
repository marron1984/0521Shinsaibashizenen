#!/usr/bin/env bash
# 心斎橋 禅園 - 名物すき焼き Instagram リール生成スクリプト
# 出力: output/reel_sukiyaki.mp4 (1080x1920 / 30fps / 約28秒)
# 音楽: 著作権フリーの合成ジャズ風メロウパッド (差し替え可)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/output"
TMP="$ROOT/.build_tmp"
mkdir -p "$OUT" "$TMP"

FONT="/usr/share/fonts/opentype/ipafont-gothic/ipagp.ttf"
W=1080; H=1920; FPS=30
D=3.6          # 1カットの尺(秒)
T=0.6          # トランジション(秒)
STEP=$(echo "$D - $T" | bc)

# 画像 と キャプション (line1 / line2)
IMAGES=(240619_0049.jpg 240619_0044.jpg 240619_0041.jpg 240619_0055.jpg 240619_0050.jpg 240619_0051.jpg 240619_0052.jpg 240619_0053.jpg 240619_0048.jpg)
L1=("心斎橋  禅園"      "厳選和牛を一枚ずつ" "とろける霜降り"   "目の前で仕上げる" "熱々を卵に"     "口の中でほどける" "〆は出汁を吸った" "最後の一滴まで" "この席は、ここだけ。")
L2=("名物 すき焼き"      "職人の手しごと"     "旨みがあふれる"   "特製の割下"       "くぐらせて"     "和牛の旨み"       "うどんで"         "ご馳走さま"     "ご予約はプロフィールから")

N=${#IMAGES[@]}

# ---------- 音声: ジャズ風メロウパッド (合成 / 著作権フリー) ----------
# ii-V-I 進行 ( Dm7 - G7 - Cmaj7 - Am7 ) を1コード約3.45秒で生成しループ
make_chord () {
  local name="$1"; shift
  local freqs=("$@")
  local inputs=() maps=() idx=0
  for f in "${freqs[@]}"; do
    inputs+=( -f lavfi -i "sine=frequency=${f}:duration=3.45:sample_rate=44100" )
    maps+=("[$idx]")
    idx=$((idx+1))
  done
  ffmpeg -y -loglevel error "${inputs[@]}" \
    -filter_complex "$(printf '%s' "${maps[@]}")amix=inputs=${idx}:normalize=1,\
volume=0.55,tremolo=f=4.2:d=0.35,lowpass=f=1900,highpass=f=90,\
aecho=0.8:0.7:60|140:0.35|0.22,\
afade=t=in:st=0:d=0.25,afade=t=out:st=3.05:d=0.4,aformat=sample_rates=44100:channel_layouts=stereo" \
    -t 3.45 "$TMP/chord_${name}.wav"
}

make_chord Dm7  293.66 349.23 440.00 523.25
make_chord G7   196.00 246.94 293.66 349.23
make_chord Cmaj 261.63 329.63 392.00 493.88
make_chord Am7  220.00 261.63 329.63 392.00

# コードを連結 → ループして全長分の音楽を作成
printf "file '%s'\n" "$TMP/chord_Dm7.wav" "$TMP/chord_G7.wav" "$TMP/chord_Cmaj.wav" "$TMP/chord_Am7.wav" > "$TMP/audio_list.txt"
TOTAL=$(echo "$N * $D - ($N - 1) * $T" | bc)
ffmpeg -y -loglevel error -stream_loop 6 -f concat -safe 0 -i "$TMP/audio_list.txt" \
  -af "aloop=loop=0:size=0,volume=0.9,afade=t=in:st=0:d=1.0,afade=t=out:st=$(echo "$TOTAL - 1.5" | bc):d=1.5" \
  -t "$TOTAL" "$TMP/music.wav"

# ---------- 動画: 各カットを生成 (ぼかし背景 + フィット + ゆるやかズーム + テロップ) ----------
esc () { printf '%s' "$1" | sed "s/'/\\\\\\\\'/g; s/:/\\\\:/g"; }

for i in $(seq 0 $((N-1))); do
  img="$ROOT/${IMAGES[$i]}"
  t1="$(esc "${L1[$i]}")"
  t2="$(esc "${L2[$i]}")"
  # 偶数カットはズームイン、奇数カットはズームアウトで変化をつける
  if [ $((i % 2)) -eq 0 ]; then
    ZEXP="1.0+0.0009*in"
  else
    ZEXP="1.10-0.0009*in"
  fi
  FR=$(echo "$D * $FPS / 1" | bc)

  ffmpeg -y -loglevel error -loop 1 -framerate $FPS -t "$D" -i "$img" \
    -filter_complex "
      [0:v]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},gblur=sigma=28,eq=brightness=-0.07:saturation=1.05[bg];
      [0:v]scale=${W}:${H}:force_original_aspect_ratio=decrease[fg];
      [bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1[base];
      [base]zoompan=z='${ZEXP}':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${W}x${H}:fps=${FPS}[zp];
      [zp]eq=saturation=1.08:contrast=1.04,
          drawbox=x=0:y=ih-560:w=iw:h=560:color=black@0.0:t=fill,
          drawtext=fontfile='${FONT}':text='${t1}':fontcolor=white:fontsize=82:borderw=5:bordercolor=black@0.55:shadowcolor=black@0.5:shadowx=2:shadowy=3:x=(w-text_w)/2:y=h-360:alpha='if(lt(t,0.4),t/0.4,if(gt(t,${D}-0.5),(${D}-t)/0.5,1))',
          drawtext=fontfile='${FONT}':text='${t2}':fontcolor=white:fontsize=52:borderw=4:bordercolor=black@0.55:shadowcolor=black@0.5:shadowx=2:shadowy=2:x=(w-text_w)/2:y=h-250:alpha='if(lt(t,0.5),t/0.5,if(gt(t,${D}-0.5),(${D}-t)/0.5,1))',
          format=yuv420p[v]
    " -map "[v]" -r $FPS -c:v libx264 -preset medium -crf 18 -t "$D" "$TMP/clip_$i.mp4"
done

# ---------- xfade で連結 ----------
INPUTS=()
for i in $(seq 0 $((N-1))); do INPUTS+=( -i "$TMP/clip_$i.mp4" ); done

FC=""
PREV="[0:v]"
for i in $(seq 1 $((N-1))); do
  OFFSET=$(echo "$i * $STEP" | bc)
  if [ "$i" -eq $((N-1)) ]; then LBL="[vout]"; else LBL="[x$i]"; fi
  FC="${FC}${PREV}[$i:v]xfade=transition=fade:duration=${T}:offset=${OFFSET}${LBL};"
  PREV="[x$i]"
done
FC="${FC%;}"

ffmpeg -y -loglevel error "${INPUTS[@]}" -i "$TMP/music.wav" \
  -filter_complex "$FC" \
  -map "[vout]" -map "${N}:a" \
  -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -r $FPS \
  -c:a aac -b:a 192k -ar 44100 \
  -movflags +faststart -shortest \
  "$OUT/reel_sukiyaki.mp4"

rm -rf "$TMP"
echo "DONE -> $OUT/reel_sukiyaki.mp4"
