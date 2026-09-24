#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE

#include <windows.h>
#include <wincodec.h>
#include <stdint.h>
#include <limits.h>
#include <cmath>
#include <string>
#include <utility>

extern "C" {
#include <emacs-module.h>
}

int plugin_is_GPL_compatible;

static HWND g_anchor = NULL;
static HWND g_owner = NULL;
static HWND g_overlay = NULL;

static int g_width = 260;
static int g_height = 180;
static int g_margin_x = 24;
static int g_margin_y = 24;
static BYTE g_alpha = 160;

static HBITMAP g_bitmap = NULL;
static SIZE g_bitmap_size = {0, 0};

static const wchar_t *kClassName = L"EmacsFrameOverlayPrototypeV2";

enum class OverlayPosition : int
{
  TopLeft = 0,
  TopRight = 1,
  BottomLeft = 2,
  BottomRight = 3,
  Center = 4
};

static OverlayPosition g_position = OverlayPosition::BottomRight;

template <typename T>
class ComPtr
{
public:
  ComPtr() = default;

  ~ComPtr()
  {
    reset();
  }

  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  T* get() const
  {
    return ptr_;
  }

  T** put()
  {
    reset();
    return &ptr_;
  }

  T* operator->() const
  {
    return ptr_;
  }

  explicit operator bool() const
  {
    return ptr_ != nullptr;
  }

  void reset()
  {
    if (ptr_) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

private:
  T* ptr_ = nullptr;
};

static void DeleteBitmap()
{
  if (g_bitmap) {
    DeleteObject(g_bitmap);
    g_bitmap = NULL;
  }

  g_bitmap_size.cx = 0;
  g_bitmap_size.cy = 0;
}

static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
  switch (msg) {
  case WM_NCHITTEST:
    return HTTRANSPARENT;

  case WM_MOUSEACTIVATE:
    return MA_NOACTIVATE;

  case WM_ERASEBKGND:
    return 1;

  case WM_PAINT: {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);

    // PNG mode is drawn by UpdateLayeredWindow.
    if (!g_bitmap) {
      RECT rc;
      GetClientRect(hwnd, &rc);

      HBRUSH brush = CreateSolidBrush(RGB(255, 64, 128));
      FillRect(dc, &rc, brush);
      DeleteObject(brush);

      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, RGB(255, 255, 255));

      const wchar_t *text = L"Emacs Frame Overlay";
      DrawTextW(dc, text, -1, &rc,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }

    EndPaint(hwnd, &ps);
    return 0;
  }

  case WM_DESTROY:
    if (hwnd == g_overlay)
      g_overlay = NULL;
    return 0;
  }

  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static bool RegisterOverlayClass()
{
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = OverlayWndProc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
  wc.lpszClassName = kClassName;

  if (RegisterClassExW(&wc))
    return true;

  return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

static bool CreateOverlayWindow()
{
  if (!RegisterOverlayClass())
    return false;

  if (g_overlay && IsWindow(g_overlay))
    DestroyWindow(g_overlay);

  g_overlay = CreateWindowExW(
    WS_EX_LAYERED |
    WS_EX_TRANSPARENT |
    WS_EX_NOACTIVATE |
    WS_EX_TOOLWINDOW,
    kClassName,
    L"",
    WS_POPUP,
    0, 0, 1, 1,
    g_owner,
    NULL,
    GetModuleHandleW(NULL),
    NULL);

  return g_overlay != NULL;
}

static bool CalculateOverlayPosition(const SIZE& overlay_size,
                                     POINT& destination)
{
  if (!g_anchor || !IsWindow(g_anchor))
    return false;

  RECT rc;
  if (!GetClientRect(g_anchor, &rc))
    return false;

  POINT origin = { rc.left, rc.top };
  if (!ClientToScreen(g_anchor, &origin))
    return false;

  const int client_width = rc.right - rc.left;
  const int client_height = rc.bottom - rc.top;

  const int left = origin.x + g_margin_x;
  const int right = origin.x + client_width - overlay_size.cx - g_margin_x;
  const int top = origin.y + g_margin_y;
  const int bottom = origin.y + client_height - overlay_size.cy - g_margin_y;
  const int center_x = origin.x + (client_width - overlay_size.cx) / 2;
  const int center_y = origin.y + (client_height - overlay_size.cy) / 2;

  int x = right;
  int y = bottom;

  switch (g_position) {
  case OverlayPosition::TopLeft:
    x = left;
    y = top;
    break;

  case OverlayPosition::TopRight:
    x = right;
    y = top;
    break;

  case OverlayPosition::BottomLeft:
    x = left;
    y = bottom;
    break;

  case OverlayPosition::BottomRight:
    x = right;
    y = bottom;
    break;

  case OverlayPosition::Center:
    x = center_x;
    y = center_y;
    break;
  }

  // If the image is larger than the frame, keep its top-left corner from
  // moving outside the frame. The image itself may still extend past it.
  if (x < origin.x)
    x = origin.x;

  if (y < origin.y)
    y = origin.y;

  destination.x = x;
  destination.y = y;
  return true;
}

static bool LoadPngToBitmap(const wchar_t* path, double scale)
{
  if (!path || scale <= 0.0 || !std::isfinite(scale))
    return false;

  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // If COM was initialized with a different apartment model, WIC can still
  // be used; do not balance that initialization with CoUninitialize here.
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
    return false;

  const bool need_co_uninitialize = SUCCEEDED(hr);

  struct CoGuard
  {
    bool enabled;

    ~CoGuard()
    {
      if (enabled)
        CoUninitialize();
    }
  } co_guard { need_co_uninitialize };

  ComPtr<IWICImagingFactory> factory;

  hr = CoCreateInstance(
    CLSID_WICImagingFactory,
    nullptr,
    CLSCTX_INPROC_SERVER,
    IID_IWICImagingFactory,
    reinterpret_cast<void**>(factory.put()));

  if (FAILED(hr))
    return false;

  ComPtr<IWICBitmapDecoder> decoder;

  hr = factory->CreateDecoderFromFilename(
    path,
    nullptr,
    GENERIC_READ,
    WICDecodeMetadataCacheOnLoad,
    decoder.put());

  if (FAILED(hr))
    return false;

  ComPtr<IWICBitmapFrameDecode> frame;

  hr = decoder->GetFrame(0, frame.put());

  if (FAILED(hr))
    return false;

  UINT source_width = 0;
  UINT source_height = 0;

  hr = frame->GetSize(&source_width, &source_height);

  if (FAILED(hr) || source_width == 0 || source_height == 0)
    return false;

  const double scaled_width_value =
    std::round(static_cast<double>(source_width) * scale);
  const double scaled_height_value =
    std::round(static_cast<double>(source_height) * scale);

  if (!std::isfinite(scaled_width_value) ||
      !std::isfinite(scaled_height_value) ||
      scaled_width_value < 1.0 ||
      scaled_height_value < 1.0 ||
      scaled_width_value > static_cast<double>(UINT_MAX) ||
      scaled_height_value > static_cast<double>(UINT_MAX))
    return false;

  const UINT scaled_width = static_cast<UINT>(scaled_width_value);
  const UINT scaled_height = static_cast<UINT>(scaled_height_value);

  ComPtr<IWICBitmapScaler> scaler;
  IWICBitmapSource *source = frame.get();

  if (scaled_width != source_width || scaled_height != source_height) {
    hr = factory->CreateBitmapScaler(scaler.put());

    if (FAILED(hr))
      return false;

    hr = scaler->Initialize(
      frame.get(),
      scaled_width,
      scaled_height,
      WICBitmapInterpolationModeFant);

    if (FAILED(hr))
      return false;

    source = scaler.get();
  }

  ComPtr<IWICFormatConverter> converter;

  hr = factory->CreateFormatConverter(converter.put());

  if (FAILED(hr))
    return false;

  hr = converter->Initialize(
    source,
    GUID_WICPixelFormat32bppPBGRA,
    WICBitmapDitherTypeNone,
    nullptr,
    0.0,
    WICBitmapPaletteTypeCustom);

  if (FAILED(hr))
    return false;

  UINT width = 0;
  UINT height = 0;

  hr = converter->GetSize(&width, &height);

  if (FAILED(hr) || width == 0 || height == 0)
    return false;

  if (width > static_cast<UINT>(LONG_MAX) ||
      height > static_cast<UINT>(LONG_MAX))
    return false;

  if (width > UINT_MAX / 4)
    return false;

  const UINT stride = width * 4;

  if (height > UINT_MAX / stride)
    return false;

  const UINT buffer_size = stride * height;

  BITMAPINFO bitmap_info {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = static_cast<LONG>(width);
  bitmap_info.bmiHeader.biHeight = -static_cast<LONG>(height); // top-down DIB
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc)
    return false;

  HBITMAP bitmap = CreateDIBSection(
    screen_dc,
    &bitmap_info,
    DIB_RGB_COLORS,
    &bits,
    nullptr,
    0);

  ReleaseDC(nullptr, screen_dc);

  if (!bitmap || !bits) {
    if (bitmap)
      DeleteObject(bitmap);

    return false;
  }

  hr = converter->CopyPixels(
    nullptr,
    stride,
    buffer_size,
    static_cast<BYTE*>(bits));

  if (FAILED(hr)) {
    DeleteObject(bitmap);
    return false;
  }

  // Replace the currently displayed bitmap only after the new one is ready.
  DeleteBitmap();

  g_bitmap = bitmap;
  g_bitmap_size.cx = static_cast<LONG>(width);
  g_bitmap_size.cy = static_cast<LONG>(height);

  return true;
}

static bool EmacsStringToWide(emacs_env *env,
                              emacs_value value,
                              std::wstring& out) noexcept
{
  try {
    ptrdiff_t utf8_size = 0;

    if (!env->copy_string_contents(env, value, nullptr, &utf8_size))
      return false;

    if (utf8_size <= 0)
      return false;

    std::string utf8(static_cast<size_t>(utf8_size), '\0');

    if (!env->copy_string_contents(env, value, utf8.data(), &utf8_size))
      return false;

    // copy_string_contents includes the terminating NUL in its size.
    const int source_length = static_cast<int>(utf8_size - 1);

    if (source_length < 0)
      return false;

    if (source_length == 0) {
      out.clear();
      return true;
    }

    const int wide_length = MultiByteToWideChar(
      CP_UTF8,
      MB_ERR_INVALID_CHARS,
      utf8.data(),
      source_length,
      nullptr,
      0);

    if (wide_length <= 0)
      return false;

    std::wstring wide(static_cast<size_t>(wide_length), L'\0');

    const int converted = MultiByteToWideChar(
      CP_UTF8,
      MB_ERR_INVALID_CHARS,
      utf8.data(),
      source_length,
      wide.data(),
      wide_length);

    if (converted != wide_length)
      return false;

    out = std::move(wide);
    return true;
  }
  catch (...) {
    return false;
  }
}

static bool UpdateOverlayBitmap()
{
  if (!g_overlay || !g_anchor || !g_bitmap)
    return false;

  if (!IsWindow(g_overlay) || !IsWindow(g_anchor))
    return false;

  POINT destination {};
  if (!CalculateOverlayPosition(g_bitmap_size, destination))
    return false;

  POINT source = { 0, 0 };
  SIZE size = g_bitmap_size;

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc)
    return false;

  HDC memory_dc = CreateCompatibleDC(screen_dc);
  if (!memory_dc) {
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ old_bitmap = SelectObject(memory_dc, g_bitmap);
  if (!old_bitmap || old_bitmap == HGDI_ERROR) {
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.BlendFlags = 0;
  blend.SourceConstantAlpha = g_alpha;
  blend.AlphaFormat = AC_SRC_ALPHA;

  const BOOL updated = UpdateLayeredWindow(
    g_overlay,
    screen_dc,
    &destination,
    &size,
    memory_dc,
    &source,
    0,
    &blend,
    ULW_ALPHA);

  SelectObject(memory_dc, old_bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  return updated != FALSE;
}

static bool SyncOverlay()
{
  if (!g_overlay || !g_anchor || !IsWindow(g_overlay) || !IsWindow(g_anchor))
    return false;

  if (g_bitmap)
    return UpdateOverlayBitmap();

  SIZE size = { g_width, g_height };
  POINT destination {};

  if (!CalculateOverlayPosition(size, destination))
    return false;

  return SetWindowPos(
    g_overlay,
    HWND_TOP,
    destination.x,
    destination.y,
    g_width,
    g_height,
    SWP_NOACTIVATE | SWP_SHOWWINDOW) != FALSE;
}

static emacs_value Qt(emacs_env *env)
{
  return env->intern(env, "t");
}

static emacs_value Qnil(emacs_env *env)
{
  return env->intern(env, "nil");
}

static int64_t GetInteger(emacs_env *env, emacs_value value)
{
  return env->extract_integer(env, value);
}

static double GetFloat(emacs_env *env, emacs_value value)
{
  return env->extract_float(env, value);
}

static BYTE ClampAlpha(int64_t alpha)
{
  if (alpha < 0)
    return 0;

  if (alpha > 255)
    return 255;

  return static_cast<BYTE>(alpha);
}

static OverlayPosition DecodePosition(int64_t position)
{
  switch (position) {
  case 0:
    return OverlayPosition::TopLeft;
  case 1:
    return OverlayPosition::TopRight;
  case 2:
    return OverlayPosition::BottomLeft;
  case 4:
    return OverlayPosition::Center;
  case 3:
  default:
    return OverlayPosition::BottomRight;
  }
}

static emacs_value Fshow(emacs_env *env,
                         ptrdiff_t nargs,
                         emacs_value *args,
                         void *data) noexcept
{
  (void)nargs;
  (void)data;

  const int64_t anchor_value = GetInteger(env, args[0]);
  const int64_t owner_value  = GetInteger(env, args[1]);
  const int64_t width_value  = GetInteger(env, args[2]);
  const int64_t height_value = GetInteger(env, args[3]);
  const int64_t alpha_value  = GetInteger(env, args[4]);

  g_anchor = (HWND)(uintptr_t)anchor_value;
  g_owner  = (HWND)(uintptr_t)owner_value;

  if (!IsWindow(g_anchor))
    return Qnil(env);

  if (!IsWindow(g_owner))
    g_owner = GetAncestor(g_anchor, GA_ROOT);

  if (!IsWindow(g_owner))
    return Qnil(env);

  g_width = width_value > 1 ? static_cast<int>(width_value) : 260;
  g_height = height_value > 1 ? static_cast<int>(height_value) : 180;
  g_alpha = ClampAlpha(alpha_value);
  g_position = OverlayPosition::BottomRight;
  g_margin_x = 24;
  g_margin_y = 24;

  DeleteBitmap();

  // Recreate the layered window when switching between the solid mode and
  // UpdateLayeredWindow-based PNG mode.
  if (!CreateOverlayWindow())
    return Qnil(env);

  if (!SetLayeredWindowAttributes(g_overlay, 0, g_alpha, LWA_ALPHA))
    return Qnil(env);

  ShowWindow(g_overlay, SW_SHOWNOACTIVATE);
  UpdateWindow(g_overlay);

  return SyncOverlay() ? Qt(env) : Qnil(env);
}

static emacs_value FshowFile(emacs_env *env,
                             ptrdiff_t nargs,
                             emacs_value *args,
                             void *data) noexcept
{
  (void)data;

  const int64_t anchor_value = GetInteger(env, args[0]);
  g_anchor = (HWND)(uintptr_t)anchor_value;
  g_owner = g_anchor;

  if (!IsWindow(g_anchor))
    return Qnil(env);

  std::wstring path;
  if (!EmacsStringToWide(env, args[1], path))
    return Qnil(env);

  if (path.empty())
    return Qnil(env);

  // Keep the original two-argument prototype call working. Additional
  // arguments are optional and are supplied by frame-overlay.el.
  double scale = 1.0;
  OverlayPosition position = OverlayPosition::BottomRight;
  int margin_x = 24;
  int margin_y = 24;
  BYTE alpha = 255;

  if (nargs >= 3)
    scale = GetFloat(env, args[2]);

  if (nargs >= 4)
    position = DecodePosition(GetInteger(env, args[3]));

  if (nargs >= 5)
    margin_x = static_cast<int>(GetInteger(env, args[4]));

  if (nargs >= 6)
    margin_y = static_cast<int>(GetInteger(env, args[5]));

  if (nargs >= 7)
    alpha = ClampAlpha(GetInteger(env, args[6]));

  if (scale <= 0.0 || !std::isfinite(scale))
    return Qnil(env);

  g_position = position;
  g_margin_x = margin_x;
  g_margin_y = margin_y;
  g_alpha = alpha;

  if (!LoadPngToBitmap(path.c_str(), scale))
    return Qnil(env);

  // Recreate the layered window because a window previously configured with
  // SetLayeredWindowAttributes should not be reused for UpdateLayeredWindow.
  if (!CreateOverlayWindow())
    return Qnil(env);

  if (!UpdateOverlayBitmap())
    return Qnil(env);

  ShowWindow(g_overlay, SW_SHOWNOACTIVATE);
  return Qt(env);
}

static emacs_value Fsync(emacs_env *env,
                         ptrdiff_t nargs,
                         emacs_value *args,
                         void *data) noexcept
{
  (void)nargs;
  (void)args;
  (void)data;

  return SyncOverlay() ? Qt(env) : Qnil(env);
}

static emacs_value Fhide(emacs_env *env,
                         ptrdiff_t nargs,
                         emacs_value *args,
                         void *data) noexcept
{
  (void)nargs;
  (void)args;
  (void)data;

  if (g_overlay && IsWindow(g_overlay)) {
    ShowWindow(g_overlay, SW_HIDE);
    return Qt(env);
  }

  return Qnil(env);
}

static emacs_value Fdestroy(emacs_env *env,
                            ptrdiff_t nargs,
                            emacs_value *args,
                            void *data) noexcept
{
  (void)nargs;
  (void)args;
  (void)data;

  if (g_overlay && IsWindow(g_overlay))
    DestroyWindow(g_overlay);

  g_overlay = NULL;
  g_anchor = NULL;
  g_owner = NULL;

  DeleteBitmap();

  return Qt(env);
}

static void BindFunction(emacs_env *env,
                         const char *name,
                         emacs_value function)
{
  emacs_value symbol = env->intern(env, name);
  emacs_value args[] = { symbol, function };

  env->funcall(env, env->intern(env, "fset"), 2, args);
}

static emacs_value MakeFunction(
  emacs_env *env,
  ptrdiff_t min_arity,
  ptrdiff_t max_arity,
  emacs_value (*fn)(emacs_env *, ptrdiff_t, emacs_value *, void *) noexcept,
  const char *doc)
{
  return env->make_function(env, min_arity, max_arity, fn, doc, NULL);
}

extern "C" int emacs_module_init(struct emacs_runtime *runtime) noexcept
{
  emacs_env *env = runtime->get_environment(runtime);

  BindFunction(
    env,
    "frame-overlay-module-show",
    MakeFunction(env, 5, 5, Fshow,
                 "Show the solid prototype overlay."));

  BindFunction(
    env,
    "frame-overlay-module-show-file",
    MakeFunction(env, 2, 7, FshowFile,
                 "Show PNG FILE on HWND. Optional SCALE, POSITION, MARGIN-X, MARGIN-Y and ALPHA configure the image."));

  BindFunction(
    env,
    "frame-overlay-module-sync",
    MakeFunction(env, 0, 0, Fsync,
                 "Synchronize the overlay with the Emacs frame."));

  BindFunction(
    env,
    "frame-overlay-module-hide",
    MakeFunction(env, 0, 0, Fhide,
                 "Hide the overlay."));

  BindFunction(
    env,
    "frame-overlay-module-destroy",
    MakeFunction(env, 0, 0, Fdestroy,
                 "Destroy the overlay window and loaded bitmap."));

  emacs_value provide_args[] = {
    env->intern(env, "frame-overlay-module")
  };

  env->funcall(env, env->intern(env, "provide"), 1, provide_args);

  return 0;
}
