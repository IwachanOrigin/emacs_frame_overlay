// SPDX-License-Identifier: GPL-3.0-or-later
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE

#include "video_player.hpp"

#include <mfapi.h>
#include <mfidl.h>
#include <mferror.h>

#include <cstddef>
#include <cstdint>
#include <climits>
#include <cstring>
#include <utility>

namespace
{
// Local COM pointers are automatically released when leaving a method.
template <typename T>
class ComPtr
{
public:
  ~ComPtr() { if (value_) value_->Release(); }
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;
  ComPtr() = default;

  T* get() const { return value_; }
  T** put() { return &value_; }
  T* operator->() const { return value_; }

private:
  T* value_ = nullptr;
};

// Lock a decoded RGB32 buffer and expose the first row plus row stride.
// Some Media Foundation buffers support IMF2DBuffer, others only Lock().
// Its destructor ALWAYS unlocks, including when a copy operation fails.
class Rgb32BufferLock
{
public:
  ~Rgb32BufferLock()
  {
    if (locked_2d_) buffer_2d_->Unlock2D();
    if (locked_simple_) buffer_->Unlock();
  }

  Rgb32BufferLock(const Rgb32BufferLock&) = delete;
  Rgb32BufferLock& operator=(const Rgb32BufferLock&) = delete;
  Rgb32BufferLock() = default;

  bool lock(IMFMediaBuffer* buffer, IMFMediaType* type,
            UINT width, UINT height) noexcept
  {
    if (!buffer || !type || !width || !height || width > UINT_MAX / 4)
    {
      return false;
    }
    
    buffer_ = buffer;
    const UINT row_bytes = width * 4;

    const HRESULT query_hr = buffer->QueryInterface(
      IID_IMF2DBuffer, reinterpret_cast<void**>(buffer_2d_.put()));

    if (SUCCEEDED(query_hr))
    {
      if (FAILED(buffer_2d_->Lock2D(&first_row_, &pitch_)))
        return false;
      locked_2d_ = true;
    }
    else
    {
      BYTE* memory_start = nullptr;
      DWORD max_length = 0;
      DWORD current_length = 0;
      if (FAILED(buffer->Lock(&memory_start, &max_length, &current_length)))
        return false;
      locked_simple_ = true;

      UINT32 encoded_pitch = 0;
      if (SUCCEEDED(type->GetUINT32(MF_MT_DEFAULT_STRIDE, &encoded_pitch)))
      {
        pitch_ = static_cast<LONG>(encoded_pitch);
      }
      else if (FAILED(MFGetStrideForBitmapInfoHeader(
                        MFVideoFormat_RGB32.Data1, width, &pitch_)))
      {
        return false;
      }
      
      const int64_t step = pitch_ < 0 ? -int64_t(pitch_) : int64_t(pitch_);
      const uint64_t required = uint64_t(step) * (height - 1) + row_bytes;
      if (!memory_start || step < row_bytes || required > current_length)
      {
        return false;
      }
        
      // Negative pitch: row 0 is at the end of the allocated buffer.
      first_row_ = (pitch_ < 0)
        ? memory_start + static_cast<size_t>(step) * (height - 1)
        : memory_start;
    }

    const int64_t step = pitch_ < 0 ? -int64_t(pitch_) : int64_t(pitch_);
    return first_row_ != nullptr && step >= row_bytes;
  }

  BYTE* firstRow() const noexcept { return first_row_; }
  LONG pitch() const noexcept { return pitch_; }

private:
  IMFMediaBuffer* buffer_ = nullptr;  // Borrowed. The caller owns it.
  ComPtr<IMF2DBuffer> buffer_2d_;
  BYTE* first_row_ = nullptr;
  LONG pitch_ = 0;
  bool locked_2d_ = false;
  bool locked_simple_ = false;
};

// RGB32 bytes are B, G, R, unused. For UpdateLayeredWindow the last byte
// must be alpha, so copy the rows and replace the unused byte with 255.
bool copyRgb32ToBgra(
  IMFMediaBuffer* buffer,
  IMFMediaType* type,
  UINT width,
  UINT height,
  VideoFrame& output) noexcept
{
  if (!buffer || !type || width == 0 || height == 0 || width > UINT_MAX / 4)
  {
    return false;
  }
    

  const UINT stride = width * 4;
  if (height > UINT_MAX / stride)
  {
    return false;
  }
  
  try
  {
    VideoFrame result;
    result.width = width;
    result.height = height;
    result.stride = stride;
    result.pixels.resize(static_cast<size_t>(stride) * height);

    Rgb32BufferLock view;
    if (!view.lock(buffer, type, width, height))
    {
      return false;
    }
    
    for (UINT y = 0; y < height; ++y)
    {
      const BYTE* src = view.firstRow() + ptrdiff_t(view.pitch()) * y;
      BYTE* dst = result.pixels.data() + static_cast<size_t>(stride) * y;
      std::memcpy(dst, src, stride);
      for (UINT x = 0; x < width; ++x)
      {
        dst[x * 4 + 3] = 255;
      }
    }

    output = std::move(result);
    return true;
  }
  catch (...)
  {
    return false;
  }
}
} // namespace

VideoPlayer::~VideoPlayer()
{
  close();
}

void VideoPlayer::setError(const char* step, HRESULT code) noexcept
{
  error_step_ = step;
  error_code_ = code;
}

// Phase 1: initialize the APIs used by the decoder.
bool VideoPlayer::initializeRuntime() noexcept
{
  const HRESULT com_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (SUCCEEDED(com_hr))
  {
    com_initialized_ = true;
  }
  else if (com_hr != RPC_E_CHANGED_MODE)
  {
    setError("CoInitializeEx", com_hr);
    return false;
  }
  // RPC_E_CHANGED_MODE means another COM apartment model is active.
  // MF can still be used, but we must NOT call CoUninitialize for it.

  const HRESULT mf_hr = MFStartup(MF_VERSION);
  if (FAILED(mf_hr))
  {
    setError("MFStartup", mf_hr);
    return false;
  }
  mf_started_ = true;
  return true;
}

// Phase 2: create a Source Reader for the local file.
bool VideoPlayer::createReader(const std::wstring& path) noexcept
{
  ComPtr<IMFAttributes> attributes;
  HRESULT hr = MFCreateAttributes(attributes.put(), 1);
  if (FAILED(hr))
  {
    setError("MFCreateAttributes", hr);
    return false;
  }

  hr = attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
  if (FAILED(hr))
  {
    setError("ENABLE_VIDEO_PROCESSING", hr);
    return false;
  }

  hr = MFCreateSourceReaderFromURL(path.c_str(), attributes.get(), &reader_);
  if (FAILED(hr))
  {
    setError("MFCreateSourceReaderFromURL", hr);
    return false;
  }
  return true;
}

// Phase 3: ignore the audio streams and select only video.
bool VideoPlayer::selectVideoStream() noexcept
{
  HRESULT hr = reader_->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE);
  if (FAILED(hr))
  {
    setError("SetStreamSelection(all, false)", hr);
    return false;
  }

  hr = reader_->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
  if (FAILED(hr))
  {
    setError("SetStreamSelection(video, true)", hr);
    return false;
  }
  return true;
}

// Phase 4: ask Source Reader to return decoded RGB32 frames.
bool VideoPlayer::configureRgb32Output() noexcept
{
  ComPtr<IMFMediaType> rgb32;
  HRESULT hr = MFCreateMediaType(rgb32.put());
  if (FAILED(hr))
  {
    setError("MFCreateMediaType", hr);
    return false;
  }

  hr = rgb32->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr))
  {
    hr = rgb32->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  }
  if (FAILED(hr))
  {
    setError("Set media type RGB32", hr);
    return false;
  }

  hr = reader_->SetCurrentMediaType(
    MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, rgb32.get());
  if (FAILED(hr))
  {
    setError("SetCurrentMediaType(RGB32)", hr);
    return false;
  }
  return true;
}

// A simple sequence to read from top to bottom. A later version will create
// and use this object entirely on a dedicated decoder thread.
bool VideoPlayer::open(const std::wstring& path) noexcept
{
  close();
  error_step_ = nullptr;
  error_code_ = S_OK;

  if (path.empty())
  {
    setError("Empty path", E_INVALIDARG);
    return false;
  }

  if (!initializeRuntime() ||
      !createReader(path) ||
      !selectVideoStream() ||
      !configureRgb32Output())
  {
    close(); // Preserve error_step_/error_code_ for diagnostics.
    return false;
  }
  return true;
}

// Phase 5: turn one decoded Media Foundation sample into our VideoFrame.
bool VideoPlayer::convertSample(IMFSample* sample, LONGLONG timestamp,
                                VideoFrame& frame) noexcept
{
  ComPtr<IMFMediaType> actual_type;
  HRESULT hr = reader_->GetCurrentMediaType(
    MF_SOURCE_READER_FIRST_VIDEO_STREAM, actual_type.put());
  if (FAILED(hr))
  {
    setError("GetCurrentMediaType", hr);
    return false;
  }

  UINT width = 0, height = 0;
  hr = MFGetAttributeSize(actual_type.get(), MF_MT_FRAME_SIZE, &width, &height);
  if (FAILED(hr))
  {
    setError("MFGetAttributeSize", hr);
    return false;
  }

  ComPtr<IMFMediaBuffer> buffer;
  hr = sample->ConvertToContiguousBuffer(buffer.put());
  if (FAILED(hr))
  {
    setError("ConvertToContiguousBuffer", hr);
    return false;
  }

  VideoFrame decoded;
  if (!copyRgb32ToBgra(buffer.get(), actual_type.get(),
                       width, height, decoded))
  {
    setError("copyRgb32ToBgra", E_FAIL);
    return false;
  }

  decoded.timestamp = timestamp;
  frame = std::move(decoded);
  return true;
}

// Phase 6: read samples until one contains a decoded video frame.
VideoReadResult VideoPlayer::readNextFrame(VideoFrame& frame) noexcept
{
  if (!reader_)
  {
    setError("readNextFrame: reader is not open", E_UNEXPECTED);
    return VideoReadResult::Error;
  }

  try
  {
    for (int attempts = 0; attempts < 64; ++attempts)
    {
      DWORD stream_index = 0;
      DWORD flags = 0;
      LONGLONG timestamp = 0;
      ComPtr<IMFSample> sample;

      const HRESULT hr = reader_->ReadSample(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
        &stream_index, &flags, &timestamp, sample.put());
      if (FAILED(hr) || (flags & MF_SOURCE_READERF_ERROR))
      {
        setError("ReadSample", FAILED(hr) ? hr : E_FAIL);
        return VideoReadResult::Error;
      }
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
        return VideoReadResult::EndOfStream;
      if (!sample.get())
        continue; // A stream tick or a media-type change, not an image.

      if (!convertSample(sample.get(), timestamp, frame))
        return VideoReadResult::Error;
      return VideoReadResult::Frame;
    }
  }
  catch (...)
  {
    setError("readNextFrame exception", E_FAIL);
    return VideoReadResult::Error;
  }

  setError("readNextFrame: too many empty samples", E_FAIL);
  return VideoReadResult::Error;
}

void VideoPlayer::close() noexcept
{
  if (reader_)
  {
    reader_->Release();
    reader_ = nullptr;
  }
  if (mf_started_)
  {
    MFShutdown();
    mf_started_ = false;
  }
  if (com_initialized_)
  {
    CoUninitialize();
    com_initialized_ = false;
  }
}
