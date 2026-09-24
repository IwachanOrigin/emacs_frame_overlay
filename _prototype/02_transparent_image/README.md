# Emacs Frame Overlay Image Prototype

画像の表示を試すためのプロトタイプ。
PNGのスケール, 座標, マージン, 透過PNG表示, タイマーで動くようにする

## ファイル

- `frame-overlay-module-png.cpp` : Emacs Dynamic Module / Win32 overlay
- `frame-overlay.el` : Lisp側ラッパー

## 1. Emacs側の前提確認

Emacsで以下を評価する。

```elisp
(list
 module-file-suffix
 (fboundp 'module-load))
```

(".dll" t) なら Dynamic Module をロードできる。

次に:

```elisp
(list
 (window-system)
 (frame-parameter nil 'window-id)
 (frame-parameter nil 'outer-window-id))
```

native Windows版なら先頭が `w32` になる。
`outer-window-id` はWindows版では `nil` でOK。
このプロトタイプは `window-id` をWin32の HWND として使用する。
(w32 "67324" nil) みたいになる


## 2. emacs-module.h の場所

自前ビルドしたEmacsのソースツリーにある `src/emacs-module.h` を使います。

例:

```text
C:/work/emacs-30.2/src/emacs-module.h
```

MSYS2 UCRT64では:

```sh
ls /c/work/emacs-30.2/src/emacs-module.h
```

のみたいな場所。
全体を

``` shell
find /c -name emacs-module.h 2>/dev/null
```
で検索してもOK.少し時間がかかる。
俺の場合、「/c/software/msys2/ucrt64/local/emacs/include」にemacs-module.hがあるので
そこを利用する。

## 3. UCRT64でビルド

UCRT64 shellで、このディレクトリのsrcへ移動して:

```sh
g++ \
  -std=c++20 \
  -O2 \
  -Wall \
  -Wextra \
  -shared \
  -o frame-overlay-module-png.dll \
  frame-overlay-module-png.cpp \
  -I/c/software/msys2/ucrt64/local/emacs/include \
  -static-libgcc \
  -static-libstdc++ \
  -lgdi32 \
  -luser32 \
  -lole32 \
  -luuid \
  -lwindowscodecs
```

`-I...` はemacs-module.hがあるフォルダパスを指定する。

このプロトタイプは Win32 API だけを使っているので、追加の画像ライブラリは不要。

## 4. Emacsからロード

ファイルを例えば次へ配置した場合:

```text
C:/emacs_frame_overlay/_prototype/02_transparent_image/src
```

Emacsで:

```elisp
(module-load "C:/emacs_frame_overlay/_prototype/02_transparent_image/src/frame-overlay-module-png.dll")
(load-file
 "C:/emacs_frame_overlay/_prototype/02_transparent_image/src/frame-overlay.el")
```

登録関数をチェック

``` elisp
(fboundp 'frame-overlay-module-show-file)
```
tならOK

## 設定とAPI

`frame-overlay.el` から、透過画像の表示倍率・位置・余白・透明度・追従間隔などを設定できます。

Overlay は **EmacsのFrame単位** で表示されます。

そのため、`C-x 2` や `C-x 3` でWindowを分割しても、Overlay画像は1枚のままです。

基本的な設定例:

``` elisp
(setq frame-overlay-scale 0.35)
(setq frame-overlay-position 'bottom-right)
(setq frame-overlay-margin-x 24)
(setq frame-overlay-margin-y 24)
(setq frame-overlay-image-alpha 255)
(setq frame-overlay-auto-sync t)
(setq frame-overlay-sync-interval 0.05)

(frame-overlay-show-file "C:/path/to/test.png")
```

### frame-overlay-refresh

Frameを再描画する関数

``` elisp
(frame-overlay-refresh)
```

各関数の設定変更後に実行するとFrameに反映されます。

### frame-overlay-scale

PNG画像の表示倍率を指定します。

1.0 が原寸です。

``` elisp
(setq frame-overlay-scale 0.35)
```
1.0  = 100%
0.5  = 50%
0.35 = 35%
0.25 = 25%


### frame-overlay-position

``` elisp
(setq frame-overlay-position 'bottom-right)
```

Frame内での画像の表示位置を指定します。

指定可能な値:

top-left
top-right
bottom-left
bottom-right
center

配置イメージ:

top-left                 top-right

+--------------------+   +--------------------+
| IMAGE              |   |              IMAGE |
|                    |   |                    |
|                    |   |                    |
+--------------------+   +--------------------+


bottom-left              bottom-right

+--------------------+   +--------------------+
|                    |   |                    |
|                    |   |                    |
| IMAGE              |   |              IMAGE |
+--------------------+   +--------------------+


center

+--------------------+
|                    |
|       IMAGE        |
|                    |
+--------------------+

### frame-overlay-margin-x

``` elisp
(setq frame-overlay-margin-x 24)
```

横方向の余白をピクセル単位で指定します。

top-left や bottom-left の場合は左端からの距離、
top-right や bottom-right の場合は右端からの距離になります。

### frame-overlay-margin-y

``` elisp
(setq frame-overlay-margin-y 24)
```

縦方向の余白をピクセル単位で指定します。

上側配置では上端からの距離、
下側配置では下端からの距離になります。

### frame-overlay-image-alpha

``` elisp
(setq frame-overlay-image-alpha 255)
```

画像全体の透明度を指定します。

範囲は 0 ～ 255 です。

255 = 元画像の濃さ
128 = 約50%
96  = かなり薄い
64  = 控えめ
32  = 非常に薄い
0   = 完全透明

編集領域の中央に置く場合は、32 前後にするとかなり邪魔になりにくくなります。

なお、この値はPNGが元々持っているalpha値とは別です。

最終的な透明度は概念的には、

PNG本来のalpha
    ×
frame-overlay-image-alpha

として適用されます。

そのため、PNGの透明背景はそのまま透明です。

### frame-overlay-auto-sync

``` elisp
(setq frame-overlay-auto-sync t)
```

Emacs Frameを移動・リサイズしたときに、Overlayを自動追従させるかを指定します。

向こう時はnilを設定します。

現在はWin32イベントを直接監視する方式ではなく、Emacsのtimerを使って定期的に位置を更新しています。

Frame移動やリサイズは頻繁に発生しないため、現状のプロトタイプではこの方式を採用しています。


### frame-overlay-sync-interval

``` elisp
(setq frame-overlay-sync-interval 0.05)
```

自動追従の更新間隔を秒単位で指定します。

0.05 = 50ms  = 約20回/秒
0.10 = 100ms = 約10回/秒
0.25 = 250ms = 約4回/秒

値を小さくすると追従が滑らかになりますが、同期処理の呼び出し回数は増えます。


### frame-overlay-show-file

指定したPNG画像を現在のEmacs Frame上に表示する
``` elisp
(frame-overlay-show-file "C:/path/to/test.png")
```

内部では以下の処理を行う。

PNG読み込み
  ↓
WICでdecode
  ↓
32bit PBGRAへ変換
  ↓
指定倍率でリサイズ
  ↓
UpdateLayeredWindow
  ↓
Frame上へ透過表示

PNGが持っている透明部分はそのまま透過されます。

また、Overlayはマウス操作を透過するため、画像の上をクリックしても背面のEmacsを操作できます。

### frame-overlay-sync-now

手動で現在の位置へ画像の座標を合わせる

``` elisp
(frame-overlay-sync-now)
```

### frame-overlay-hide

オーバーレイ画像を隠す
あわせて、自動追従用のTimerも停止する

``` elisp
(frame-overlay-hide)
```

### frame-overlay-destory

Overlay Windowを破棄し、画像のネイティブリソースも解放する
自動追従タイマーも停止する

``` elisp
(frame-overlay-destroy)
```

