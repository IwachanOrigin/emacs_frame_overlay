# Emacs Frame Overlay Prototype

目的は、native Windows版Emacsの「Frame」に対して overlay HWND を1枚だけ重ね、
Emacs Windowを左右/上下に分割しても overlay が増えないことを確認することです。

テストとして半透明のピンク色矩形を表示します。

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
  -o frame-overlay-module.dll \
  frame-overlay-module.cpp \
  -I/c/software/msys2/ucrt64/local/emacs/include \
  -static-libgcc \
  -static-libstdc++ \
  -lgdi32 \
  -luser32
```

`-I...` はemacs-module.hがあるフォルダパスを指定する。

このプロトタイプは Win32 API だけを使っているので、追加の画像ライブラリは不要。

## 4. Emacsからロード

ファイルを例えば次へ配置した場合:

```text
C:/work/emacs-frame-overlay-prototype/
```

Emacsで:

```elisp
(add-to-list 'load-path "C:/work/emacs-frame-overlay-prototype/")
(module-load "C:/work/emacs-frame-overlay-prototype/frame-overlay-module.dll")
(require 'frame-overlay)
```

まず native ID を確認:

```elisp
(frame-overlay-frame-ids)
```

その後:

```elisp
(frame-overlay-show)
```

右下に半透明の矩形が出れば成功。

## 5. 試すこと

### Frameを移動する
overlay がFrameに追従しないこと。
タイマーで動くようにする。

### Frameをリサイズする
overlay が右下へ追従しないこと。
タイマーで動くようにする。

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
- PNG読み込みなし
- 複数Frame同時対応なし
- DPI変更への本格対応なし
- Frame破棄時の自動cleanupなし
- native event hookではなく50ms timerで位置追従


