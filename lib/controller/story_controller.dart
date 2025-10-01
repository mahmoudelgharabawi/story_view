import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

enum PlaybackState { pause, play, next, previous }

/// Controller to sync playback between animated child (story) views. This
/// helps make sure when stories are paused, the animation (gifs/slides) are
/// also paused.
/// Another reason for using the controller is to place the stories on `paused`
/// state when a media is loading.
class StoryController {
  /// Stream that broadcasts the playback state of the stories.
  final playbackNotifier = BehaviorSubject<PlaybackState>();

  /// Tracks if the current story item is still loading
  bool _isLoading = false;

  /// Callback to start the animation controller
  VoidCallback? _startAnimationCallback;

  /// Callback to notify when media widgets are ready
  VoidCallback? _mediaReadyCallback;

  /// Track if media is visible on screen
  bool _isMediaVisible = false;

  /// Notify listeners with a [PlaybackState.pause] state
  void pause() {
    debugPrint(
        'STORY_DEBUG: 🎮 StoryController: pause() called - isLoading: $_isLoading');
    playbackNotifier.add(PlaybackState.pause);
  }

  /// Notify listeners with a [PlaybackState.play] state
  void play() {
    debugPrint(
        'STORY_DEBUG: 🎮 StoryController: play() called - isLoading: $_isLoading');
    playbackNotifier.add(PlaybackState.play);
  }

  void next() {
    debugPrint('STORY_DEBUG_V1: 🎮 StoryController: next() called');
    playbackNotifier.add(PlaybackState.next);
  }

  void previous() {
    debugPrint('STORY_DEBUG_V1: 🎮 StoryController: previous() called');
    playbackNotifier.add(PlaybackState.previous);
  }

  /// Mark that loading has started
  void startLoading() {
    debugPrint(
        'STORY_DEBUG_V1: 🔄 StoryController: startLoading() called - was isLoading: $_isLoading');
    _isLoading = true;
    pause();

    // Notify that media widgets are ready (they've called startLoading)
    debugPrint(
        'STORY_DEBUG_V1: 🔄 StoryController: Notifying media widgets are ready');
    _mediaReadyCallback?.call();
  }

  /// Mark that loading has finished
  void finishLoading() {
    debugPrint(
        'STORY_DEBUG: ✅ StoryController: finishLoading() called - was isLoading: $_isLoading');
    _isLoading = false;
    // Don't play immediately - wait for media to be visible
    debugPrint(
        'STORY_DEBUG: ✅ StoryController: Loading finished, waiting for media visibility');
  }

  /// Mark that media is visible on screen
  void markMediaVisible() {
    debugPrint(
        'STORY_DEBUG: 👁️ StoryController: markMediaVisible() called - was visible: $_isMediaVisible');
    if (!_isMediaVisible) {
      _isMediaVisible = true;
      debugPrint(
          'STORY_DEBUG: 👁️ StoryController: Media marked as visible, calling play()');
      // Now we can safely start playing
      play();
    } else {
      debugPrint(
          'STORY_DEBUG: 👁️ StoryController: Media already marked as visible, skipping play()');
    }
  }

  /// Mark that media is no longer visible
  void markMediaNotVisible() {
    debugPrint(
        'STORY_DEBUG: 👁️ StoryController: markMediaNotVisible() called');
    _isMediaVisible = false;
  }

  /// Force play regardless of loading state (for debugging)
  void forcePlay() {
    debugPrint('STORY_DEBUG_V1: 🔧 StoryController: forcePlay() called');
    _isLoading = false;
    play();
  }

  /// Check if currently loading
  bool get isLoading => _isLoading;

  /// Check if media is visible on screen
  bool get isMediaVisible => _isMediaVisible;

  /// Set the callback to start animation
  void setStartAnimationCallback(VoidCallback callback) {
    _startAnimationCallback = callback;
  }

  /// Set the callback to notify when media widgets are ready
  void setMediaReadyCallback(VoidCallback callback) {
    debugPrint(
        'STORY_DEBUG_V1: 🎮 StoryController: setMediaReadyCallback() called');
    _mediaReadyCallback = callback;
  }

  /// Start the animation controller directly
  void startAnimation() {
    debugPrint('STORY_DEBUG_V1: 🎮 StoryController: startAnimation() called');
    _startAnimationCallback?.call();
    debugPrint(
        'STORY_DEBUG_V1: 🎮 StoryController: startAnimation callback executed');
  }

  /// Remember to call dispose when the story screen is disposed to close
  /// the notifier stream.
  void dispose() {
    playbackNotifier.close();
  }
}
