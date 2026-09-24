# Emacs Frame Overlay Image Prototype

画像の表示を試すためのプロトタイプ。
PNGのスケール, 座標, マージン, 透過PNG表示, タイマーで動くようにする

## ファイル

- `frame-overlay-module.cpp` : Emacs Dynamic Module / Win32 overlay
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

次に透過PNGを例えば以下へ配置する
C:/emacs_frame_overlay/_prototype/02_transparent_image/src/test.png

で、

``` elisp
(let ((hwnd
       (string-to-number
        (frame-parameter nil 'window-id))))
  (frame-overlay-module-show-file
   hwnd
   "C:/emacs_frame_overlay/_prototype/02_transparent_image/src/test.png"))
```
として読み込み、tが出たら読み込みOK

そうすると

┌───────── Emacs──┐
│                             │
│                  透明       │
│                   /\_/\\    │
│                  ( o.o )    │
│                   > ^ <     │
│                             │
└──────────────┘

みたいになるはず。

## 5. 試すこと

### Frameを移動する
overlay がFrameに追従すること

### Frameをリサイズする
overlay が右下へ追従すること

### Windowを横分割する

```text
C-x 3
```

overlay が「1枚のまま」であること。

### Windowを縦分割する

```text
C-x 2
```

overlayは1枚のままであること。

### overlay上をクリックする
クリックがEmacsへ抜けることを確認する。

## 6. 終了

一時的に隠す:

```elisp
(frame-overlay-hide)
```

完全に破棄:

```elisp
(frame-overlay-destroy)
```

## 注意

これは実現性確認のためのプロトタイプです。

現段階では:
- 複数Frame同時対応なし
- DPI変更への本格対応なし
- Frame破棄時の自動cleanupなし


