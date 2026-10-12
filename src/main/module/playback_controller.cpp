// SPDX-License-Identifier: GPL-3.0-or-later
#include "playback_controller.hpp"

#include <chrono>
#include <cstdio>
#include <exception>
#include <utility>

namespace
{
std::string decoderError(const VideoPlayer& player)
{
  char code[16] = {};
  std::snprintf(code, sizeof(code), "0x%08lX",
                static_cast<unsigned long>(player.errorCode()));
  return std::string(player.errorStep() ? player.errorStep() : "Decoder error")
         + " (HRESULT " + code + ")";
}
} // namespace

PlaybackController::~PlaybackController()
{
  stop();
}

bool PlaybackController::play(const std::wstring& path, bool loop)
{
  stop();
  if (path.empty())
    return false;

  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_requested_ = false;
    state_ = PlaybackState::Starting;
    latest_frame_.reset();
    last_error_.clear();
  }

  try
  {
    // VideoPlayer is constructed inside this thread, not on Emacs's thread.
    worker_ = std::thread(&PlaybackController::playbackLoop, this, path, loop);
    return true;
  }
  catch (const std::exception& e)
  {
    reportError(e.what());
    return false;
  }
}

void PlaybackController::stop()
{
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_requested_ = true;
  }
  stop_cv_.notify_all(); // Interrupt the presentation-time wait promptly.

  // NEVER hold mutex_ while joining: the worker also needs the mutex.
  if (worker_.joinable())
    worker_.join();

  {
    std::lock_guard<std::mutex> lock(mutex_);
    latest_frame_.reset();
    state_ = PlaybackState::Stopped;
  }
}

bool PlaybackController::stopRequested() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  return stop_requested_;
}

void PlaybackController::reportError(const std::string& message)
{
  std::lock_guard<std::mutex> lock(mutex_);
  if (!stop_requested_)
  {
    last_error_ = message;
    state_ = PlaybackState::Error;
  }
}

void PlaybackController::playbackLoop(std::wstring path, bool loop)
{
  using Clock = std::chrono::steady_clock;

  try
  {
    while (!stopRequested())
    {
      // COM and Media Foundation are initialized and released by this thread.
      VideoPlayer player;
      if (!player.open(path))
      {
        reportError(decoderError(player));
        return;
      }

      bool have_first_timestamp = false;
      LONGLONG first_timestamp = 0;
      Clock::time_point playback_start{};

      while (!stopRequested())
      {
        VideoFrame frame;
        const VideoReadResult result = player.readNextFrame(frame);
        if (result == VideoReadResult::EndOfStream)
          break;
        if (result == VideoReadResult::Error)
        {
          reportError(decoderError(player));
          return;
        }

        if (!have_first_timestamp)
        {
          first_timestamp = frame.timestamp;
          playback_start = Clock::now();
          have_first_timestamp = true;
        }

        // IMFSourceReader timestamps are in 100-ns units.
        // steady_clock avoids wall-clock changes during playback.
        const double seconds = static_cast<double>(frame.timestamp - first_timestamp)
                               / 10'000'000.0;
        const auto deadline = playback_start +
          std::chrono::duration_cast<Clock::duration>(
            std::chrono::duration<double>(seconds < 0.0 ? 0.0 : seconds));

        {
          std::unique_lock<std::mutex> lock(mutex_);
          if (stop_cv_.wait_until(lock, deadline,
                                  [this] { return stop_requested_; }))
            return;

          // A one-frame mailbox: no unbounded memory queue if Emacs is busy.
          latest_frame_ = std::move(frame);
          state_ = PlaybackState::Playing;
        }
      }

      // Let the VideoPlayer destructor close the decoder on this thread.
      if (!loop || !have_first_timestamp)
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stop_requested_)
          state_ = PlaybackState::Finished;
        return;
      }
      // Loop by reopening the file on the SAME worker thread.
      // A new clock is established for the new playthrough.
    }
  }
  catch (const std::exception& e)
  {
    reportError(e.what());
  }
  catch (...)
  {
    reportError("Unexpected playback worker exception");
  }
}

bool PlaybackController::takeLatestFrame(VideoFrame& frame)
{
  std::lock_guard<std::mutex> lock(mutex_);
  if (!latest_frame_)
    return false;
  frame = std::move(*latest_frame_);
  latest_frame_.reset();
  return true;
}

PlaybackState PlaybackController::state() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  return state_;
}

std::string PlaybackController::lastError() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  return last_error_;
}
