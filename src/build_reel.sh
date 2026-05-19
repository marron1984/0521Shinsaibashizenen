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

# ダウンロードした Noto JP フォント (見出し=明朝太 / 補足=ゴシック)
FONT_TITLE="$ROOT/assets/fonts/NotoSerifJP-Bold.ttf"
FONT_SUB="$ROOT/assets/fonts/NotoSansJP-Medium.ttf"
W=1080; H=1920; FPS=30
D=3.6          # 1カットの尺(秒)
DL=5.0         # 最終ページ(予約QRカード)の表示尺(秒) ※QR読み取りのため長め
T=0.6          # トランジション(秒)
STEP=$(echo "$D - $T" | bc)

# 画像 と キャプション (line1 / line2) ※最終ページはデザイン済みカードのため文字なし
IMAGES=(240619_0049.jpg 240619_0044.jpg 240619_0041.jpg 240619_0055.jpg 240619_0050.jpg 240619_0051.jpg 240619_0052.jpg 240619_0053.jpg 240619_0048.jpg S__2719760_0.jpg)
L1=("心斎橋  禅園"      "厳選和牛を一枚ずつ" "とろける霜降り"   "目の前で仕上げる" "熱々を卵に"     "口の中でほどける" "〆は出汁を吸った" "最後の一滴まで" "この席は、ここだけ。" "")
L2=("名物 すき焼き"      "職人の手しごと"     "旨みがあふれる"   "特製の割下"       "くぐらせて"     "和牛の旨み"       "うどんで"         "ご馳走さま"     "今宵、特別な一席を" "")

N=${#IMAGES[@]}

# ---------- 音声: リポジトリ内の MP3 を BGM に採用 (軽快・明るめに調整) ----------
BGM="$ROOT/Midnight_on_the_Terrace.mp3"
BGM_TEMPO=1.12   # テンポを上げて軽快に (1.0=原曲)
TOTAL=$(echo "($N - 1) * $STEP + $DL" | bc)
# テンポアップ + 明るめEQ(高音シェルフ/低域抑制) → ループ → 全長で切り出し、フェードイン/アウト
ffmpeg -y -loglevel error -stream_loop -1 -i "$BGM" \
  -af "atempo=${BGM_TEMPO},highpass=f=70,equalizer=f=250:width_type=o:width=1.2:g=-2,treble=g=4:f=3200,equalizer=f=8000:width_type=o:width=1:g=2.5,volume=0.8,alimiter=limit=0.92:attack=5:release=60,afade=t=in:st=0:d=1.0,afade=t=out:st=$(echo "$TOTAL - 1.8" | bc):d=1.8,aformat=sample_rates=44100:channel_layouts=stereo" \
  -t "$TOTAL" "$TMP/music.wav"

# ---------- 動画: 各カットを生成 (ぼかし背景 + フィット + ゆるやかズーム + テロップ) ----------
esc () { printf '%s' "$1" | sed "s/'/\\\\\\\\'/g; s/:/\\\\:/g"; }

for i in $(seq 0 $((N-1))); do
  img="$ROOT/${IMAGES[$i]}"
  t1="$(esc "${L1[$i]}")"
  t2="$(esc "${L2[$i]}")"

  if [ "$i" -eq $((N-1)) ]; then
    # 最終ページ: 予約QRカード → 静止・テロップなし・長め表示 (QR読み取り用)
    CLIPDUR="$DL"
    ZEXP="1.0"
    TEXTCHAIN="format=yuv420p[v]"
  else
    CLIPDUR="$D"
    # 偶数カットはズームイン、奇数カットはズームアウトで変化をつける
    if [ $((i % 2)) -eq 0 ]; then
      ZEXP="1.0+0.0009*in"
    else
      ZEXP="1.10-0.0009*in"
    fi
    TEXTCHAIN="drawtext=fontfile='${FONT_TITLE}':text='${t1}':fontcolor=white:fontsize=84:borderw=5:bordercolor=black@0.55:shadowcolor=black@0.5:shadowx=2:shadowy=3:x=(w-text_w)/2:y=h-360:alpha='if(lt(t,0.4),t/0.4,if(gt(t,${D}-0.5),(${D}-t)/0.5,1))',drawtext=fontfile='${FONT_SUB}':text='${t2}':fontcolor=white:fontsize=52:borderw=4:bordercolor=black@0.55:shadowcolor=black@0.5:shadowx=2:shadowy=2:x=(w-text_w)/2:y=h-248:alpha='if(lt(t,0.5),t/0.5,if(gt(t,${D}-0.5),(${D}-t)/0.5,1))',format=yuv420p[v]"
  fi

  ffmpeg -y -loglevel error -loop 1 -framerate $FPS -t "$CLIPDUR" -i "$img" \
    -filter_complex "
      [0:v]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},gblur=sigma=28,eq=brightness=-0.07:saturation=1.05[bg];
      [0:v]scale=${W}:${H}:force_original_aspect_ratio=decrease[fg];
      [bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1[base];
      [base]zoompan=z='${ZEXP}':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${W}x${H}:fps=${FPS}[zp];
      [zp]eq=saturation=1.08:contrast=1.04,
          drawbox=x=0:y=ih-560:w=iw:h=560:color=black@0.0:t=fill,
          ${TEXTCHAIN}
    " -map "[v]" -r $FPS -c:v libx264 -preset medium -crf 18 -t "$CLIPDUR" "$TMP/clip_$i.mp4"
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
