// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef VIDEO_PLAYER_HPP_
#define VIDEO_PLAYER_HPP_

#include <windows.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <string>
#include <vector>

// One decoded image, stored top-to-bottom in 32-bit BGRA format.
// The alpha channel is always 255: video pixels are fully opaque.
struct VideoFrame
{
  std::vector<BYTE> pixels;
  UINT width = 0;
  UINT height = 0;
  UINT stride = 0;       // Number of bytes in one output row.
  LONGLONG timestamp = 0; // Presentation timestamp, in 100-ns units.
};

enum class VideoReadResult
{
  Frame,
  EndOfStream,
  Error
};

// Decodes frames with Media Foundation. It does NOT display frames or
// create a playback thread. That separation keeps the decoder testable.
//
// IMPORTANT: open(), readNextFrame(), close() and destruction must all run
// on the same thread because COM is initialized on that thread.
class VideoPlayer
{
public:
  VideoPlayer() = default;
  ~VideoPlayer();

  VideoPlayer(const VideoPlayer&) = delete;
  VideoPlayer& operator=(const VideoPlayer&) = delete;

  // 1. Open a local video file and select RGB32 output.
  bool open(const std::wstring& path) noexcept;

  // 2. Decode the next video frame. No frame timing/sleep is performed.
  VideoReadResult readNextFrame(VideoFrame& frame) noexcept;

  // 3. Release the reader and balance MF/COM initialization.
  void close() noexcept;

  // Useful when diagnosing decoder failures (e.g. unsupported profiles).
  const char* errorStep() const noexcept { return error_step_; }
  HRESULT errorCode() const noexcept { return error_code_; }

private:
  bool initializeRuntime() noexcept;
  bool createReader(const std::wstring& path) noexcept;
  bool selectVideoStream() noexcept;
  bool configureRgb32Output() noexcept;
  bool convertSample(IMFSample* sample, LONGLONG timestamp,
                     VideoFrame& frame) noexcept;
  void setError(const char* step, HRESULT code) noexcept;

  IMFSourceReader* reader_ = nullptr;
  bool com_initialized_ = false;
  bool mf_started_ = false;
  const char* error_step_ = nullptr;
  HRESULT error_code_ = S_OK;
};

#endif // VIDEO_PLAYER_HPP_


