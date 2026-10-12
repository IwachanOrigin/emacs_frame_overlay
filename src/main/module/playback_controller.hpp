// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef PLAYBACK_CONTROLLER_HPP_
#define PLAYBACK_CONTROLLER_HPP_

#include "video_player.hpp"

#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

enum class PlaybackState
{
  Stopped,
  Starting,
  Playing,
  Finished,
  Error
};

// Owns the decoding worker, but NEVER draws and NEVER calls Emacs APIs.
// The Emacs thread calls takeLatestFrame() to obtain a decoded frame.
class PlaybackController
{
public:
  PlaybackController() = default;
  ~PlaybackController();

  PlaybackController(const PlaybackController&) = delete;
  PlaybackController& operator=(const PlaybackController&) = delete;

  bool play(const std::wstring& path, bool loop);
  void stop();

  // Returns false if there is no newly decoded frame.
  // Only ONE pending frame is retained; old frames are dropped when busy.
  bool takeLatestFrame(VideoFrame& frame);
  PlaybackState state() const;
  std::string lastError() const;

private:
  void playbackLoop(std::wstring path, bool loop);
  bool stopRequested() const;
  void reportError(const std::string& message);

  mutable std::mutex mutex_;
  std::condition_variable stop_cv_;
  std::thread worker_;

  bool stop_requested_ = false;
  PlaybackState state_ = PlaybackState::Stopped;
  std::optional<VideoFrame> latest_frame_;
  std::string last_error_;
};

#endif // PLAYBACK_CONTROLLER_HPP_
