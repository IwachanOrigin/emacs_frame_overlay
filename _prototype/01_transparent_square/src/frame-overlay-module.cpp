#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdint.h>

extern "C" {
#include <emacs-module.h>
}

int plugin_is_GPL_compatible;

static HWND g_anchor = NULL;
static HWND g_owner = NULL;
static HWND g_overlay = NULL;

static int g_width = 260;
static int g_height = 180;
static int g_margin = 24;
static BYTE g_alpha = 160;

static const wchar_t *kClassName = L"EmacsFrameOverlayPrototype";

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
        RECT rc;
        GetClientRect(hwnd, &rc);
        HBRUSH brush = CreateSolidBrush(RGB(255, 64, 128));
        FillRect(dc, &rc, brush);
        DeleteObject(brush);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        const wchar_t *text = L"Emacs Frame Overlay";
        DrawTextW(dc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_DESTROY:
        if (hwnd == g_overlay) g_overlay = NULL;
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
    if (RegisterClassExW(&wc)) return true;
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

static bool SyncOverlay()
{
    if (!g_overlay || !g_anchor || !IsWindow(g_overlay) || !IsWindow(g_anchor))
        return false;
    RECT rc;
    if (!GetClientRect(g_anchor, &rc)) return false;
    POINT origin = { rc.left, rc.top };
    if (!ClientToScreen(g_anchor, &origin)) return false;
    const int client_width = rc.right - rc.left;
    const int client_height = rc.bottom - rc.top;
    int x = origin.x + client_width - g_width - g_margin;
    int y = origin.y + client_height - g_height - g_margin;
    if (x < origin.x) x = origin.x;
    if (y < origin.y) y = origin.y;
    return SetWindowPos(g_overlay, HWND_TOP, x, y, g_width, g_height,
                        SWP_NOACTIVATE | SWP_SHOWWINDOW) != FALSE;
}

static emacs_value Qt(emacs_env *env) { return env->intern(env, "t"); }
static emacs_value Qnil(emacs_env *env) { return env->intern(env, "nil"); }
static int64_t GetInteger(emacs_env *env, emacs_value value)
{
    return env->extract_integer(env, value);
}

static emacs_value Fshow(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) noexcept
{
    (void)nargs; (void)data;
    const int64_t anchor_value = GetInteger(env, args[0]);
    const int64_t owner_value  = GetInteger(env, args[1]);
    const int64_t width_value  = GetInteger(env, args[2]);
    const int64_t height_value = GetInteger(env, args[3]);
    const int64_t alpha_value  = GetInteger(env, args[4]);
    g_anchor = (HWND)(uintptr_t)anchor_value;
    g_owner  = (HWND)(uintptr_t)owner_value;
    if (!IsWindow(g_anchor)) return Qnil(env);
    if (!IsWindow(g_owner)) g_owner = GetAncestor(g_anchor, GA_ROOT);
    if (!IsWindow(g_owner)) return Qnil(env);
    g_width = width_value > 1 ? (int)width_value : 260;
    g_height = height_value > 1 ? (int)height_value : 180;
    if (alpha_value < 0) g_alpha = 0;
    else if (alpha_value > 255) g_alpha = 255;
    else g_alpha = (BYTE)alpha_value;
    if (!RegisterOverlayClass()) return Qnil(env);
    if (!g_overlay || !IsWindow(g_overlay)) {
        g_overlay = CreateWindowExW(
            WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
            kClassName, L"", WS_POPUP,
            0, 0, g_width, g_height,
            g_owner, NULL, GetModuleHandleW(NULL), NULL);
        if (!g_overlay) return Qnil(env);
    } else {
        SetWindowLongPtrW(g_overlay, GWLP_HWNDPARENT, (LONG_PTR)g_owner);
    }
    if (!SetLayeredWindowAttributes(g_overlay, 0, g_alpha, LWA_ALPHA))
        return Qnil(env);
    ShowWindow(g_overlay, SW_SHOWNOACTIVATE);
    UpdateWindow(g_overlay);
    return SyncOverlay() ? Qt(env) : Qnil(env);
}

static emacs_value Fsync(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) noexcept
{
    (void)nargs; (void)args; (void)data;
    return SyncOverlay() ? Qt(env) : Qnil(env);
}

static emacs_value Fhide(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) noexcept
{
    (void)nargs; (void)args; (void)data;
    if (g_overlay && IsWindow(g_overlay)) {
        ShowWindow(g_overlay, SW_HIDE);
        return Qt(env);
    }
    return Qnil(env);
}

static emacs_value Fdestroy(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) noexcept
{
    (void)nargs; (void)args; (void)data;
    if (g_overlay && IsWindow(g_overlay)) DestroyWindow(g_overlay);
    g_overlay = NULL;
    g_anchor = NULL;
    g_owner = NULL;
    return Qt(env);
}

static void BindFunction(emacs_env *env, const char *name, emacs_value function)
{
    emacs_value symbol = env->intern(env, name);
    emacs_value args[] = { symbol, function };
    env->funcall(env, env->intern(env, "fset"), 2, args);
}

static emacs_value MakeFunction(emacs_env *env, ptrdiff_t min_arity, ptrdiff_t max_arity,
                                emacs_value (*fn)(emacs_env *, ptrdiff_t, emacs_value *, void *) noexcept,
                                const char *doc)
{
    return env->make_function(env, min_arity, max_arity, fn, doc, NULL);
}

extern "C" int emacs_module_init(struct emacs_runtime *runtime) noexcept
{
    emacs_env *env = runtime->get_environment(runtime);
    BindFunction(env, "frame-overlay-module-show",
                 MakeFunction(env, 5, 5, Fshow, "Show a prototype overlay."));
    BindFunction(env, "frame-overlay-module-sync",
                 MakeFunction(env, 0, 0, Fsync, "Synchronize the prototype overlay."));
    BindFunction(env, "frame-overlay-module-hide",
                 MakeFunction(env, 0, 0, Fhide, "Hide the prototype overlay."));
    BindFunction(env, "frame-overlay-module-destroy",
                 MakeFunction(env, 0, 0, Fdestroy, "Destroy the prototype overlay window."));
    emacs_value provide_args[] = { env->intern(env, "frame-overlay-module") };
    env->funcall(env, env->intern(env, "provide"), 1, provide_args);
    return 0;
}
