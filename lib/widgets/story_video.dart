import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../utils.dart';
import '../controller/story_controller.dart';

class VideoLoader {
  String url;

  File? videoFile;

  Map<String, dynamic>? requestHeaders;

  LoadState state = LoadState.loading;

  VideoLoader(this.url, {this.requestHeaders});

  void loadVideo(VoidCallback onComplete) {
    if (this.videoFile != null) {
      this.state = LoadState.success;
      onComplete();
      return;
    }

    // Ensure we start with loading state
    this.state = LoadState.loading;

    final fileStream = DefaultCacheManager().getFileStream(this.url,
        headers: this.requestHeaders as Map<String, String>?);

    fileStream.listen((fileResponse) {
      if (fileResponse is FileInfo) {
        if (this.videoFile == null) {
          this.state = LoadState.success;
          this.videoFile = fileResponse.file;
          onComplete();
        }
      }
    }, onError: (error) {
      this.state = LoadState.failure;
      onComplete();
    });
  }
}

class StoryVideo extends StatefulWidget {
  final StoryController? storyController;
  final VideoLoader videoLoader;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryVideo(
    this.videoLoader, {
    Key? key,
    this.storyController,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key ?? UniqueKey());

  static StoryVideo url(
    String url, {
    StoryController? controller,
    Map<String, dynamic>? requestHeaders,
    Key? key,
    Widget? loadingWidget,
    Widget? errorWidget,
  }) {
    return StoryVideo(
      VideoLoader(url, requestHeaders: requestHeaders),
      storyController: controller,
      key: key,
      loadingWidget: loadingWidget,
      errorWidget: errorWidget,
    );
  }

  @override
  State<StatefulWidget> createState() {
    return StoryVideoState();
  }
}

class StoryVideoState extends State<StoryVideo> with WidgetsBindingObserver {
  Future<void>? playerLoader;

  StreamSubscription? _streamSubscription;

  VideoPlayerController? playerController;

  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🎥 StoryVideo: initState() called for URL: ${widget.videoLoader.url}');

    // Add observer for visibility changes
    WidgetsBinding.instance.addObserver(this);

    // Always start loading - this will pause the controller
    widget.storyController!.startLoading();

    debugPrint('STORY_DEBUG_V1: 🎥 StoryVideo: Starting to load video...');
    widget.videoLoader.loadVideo(() {
      debugPrint(
          '🎥 StoryVideo: loadVideo callback triggered - state: ${widget.videoLoader.state}');
      if (widget.videoLoader.state == LoadState.success) {
        debugPrint(
            'STORY_DEBUG: 🎥 StoryVideo: Video file loaded, initializing player...');
        this.playerController =
            VideoPlayerController.file(widget.videoLoader.videoFile!);

        // Initialize the video player and only finish loading when fully ready
        playerController!.initialize().then((v) {
          debugPrint(
              'STORY_DEBUG_V1: 🎥 StoryVideo: Video player initialized successfully');
          if (mounted) {
            setState(() {});
            // Mark loading as finished
            debugPrint(
                'STORY_DEBUG_V1: 🎥 StoryVideo: Video loaded, calling finishLoading');
            widget.storyController!.finishLoading();
            // Check visibility after video is loaded and initialized
            // Use a small delay to ensure the widget is fully rendered
            Future.delayed(Duration(milliseconds: 100), () {
              if (mounted) {
                _checkVisibility();
              }
            });

            // Fallback: if visibility detection fails, mark as visible after a delay
            Future.delayed(Duration(milliseconds: 200), () {
              if (mounted && !_isVisible) {
                debugPrint(
                    'STORY_DEBUG: 👁️ StoryVideo: Fallback - marking video as visible');
                _isVisible = true;
                widget.storyController?.markMediaVisible();
              }
            });
          }
        }).catchError((error) {
          debugPrint(
              'STORY_DEBUG: 🎥 StoryVideo: Video player initialization failed: $error');
          // If video initialization fails, still finish loading to show error state
          if (mounted) {
            setState(() {});
            widget.storyController!.finishLoading();
            // Check visibility even if video initialization failed
            _checkVisibility();
          }
        });

        if (widget.storyController != null) {
          _streamSubscription =
              widget.storyController!.playbackNotifier.listen((playbackState) {
            debugPrint(
                'STORY_DEBUG: 🎥 StoryVideo: PlaybackState changed to: $playbackState');
            if (playbackState == PlaybackState.pause) {
              playerController?.pause();
            } else {
              playerController?.play();
            }
          });
        }
      } else {
        debugPrint(
            'STORY_DEBUG: 🎥 StoryVideo: Video loading failed, finishing loading anyway');
        // If loading failed, still finish loading to show error state
        if (mounted) {
          setState(() {});
          widget.storyController!.finishLoading();
          // Check visibility even if loading failed
          _checkVisibility();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check visibility when the widget is built and video is ready
    if (widget.videoLoader.state == LoadState.success &&
        playerController != null &&
        playerController!.value.isInitialized &&
        !_isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkVisibility();
        }
      });
    }

    return Container(
      color: Colors.black,
      height: double.infinity,
      width: double.infinity,
      child: VideoContentView(
        videoLoadState: widget.videoLoader.state,
        playerController: playerController,
        loadingWidget: widget.loadingWidget,
        errorWidget: widget.errorWidget,
      ),
    );
  }

  @override
  void dispose() {
    playerController?.dispose();
    _streamSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkVisibility();
    }
  }

  void _checkVisibility() {
    debugPrint(
        'STORY_DEBUG: 👁️ StoryVideo: _checkVisibility() called - mounted: $mounted, _isVisible: $_isVisible');
    if (!mounted) return;

    // Use a post-frame callback to ensure the widget is fully rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          'STORY_DEBUG: 👁️ StoryVideo: Post-frame callback executing - mounted: $mounted, _isVisible: $_isVisible');
      if (mounted && !_isVisible) {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        debugPrint(
            'STORY_DEBUG: 👁️ StoryVideo: RenderBox found: ${renderBox != null}, hasSize: ${renderBox?.hasSize}');
        if (renderBox != null && renderBox.hasSize) {
          final position = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          final screenSize = MediaQuery.of(context).size;

          debugPrint(
              'STORY_DEBUG: 👁️ StoryVideo: Position: $position, Size: $size, ScreenSize: $screenSize');

          // Check if the widget is visible on screen
          final isVisible = position.dx < screenSize.width &&
              position.dy < screenSize.height &&
              position.dx + size.width > 0 &&
              position.dy + size.height > 0;

          debugPrint(
              'STORY_DEBUG: 👁️ StoryVideo: Calculated isVisible: $isVisible');

          if (isVisible && !_isVisible) {
            _isVisible = true;
            debugPrint(
                'STORY_DEBUG: 👁️ StoryVideo: Video is now visible on screen');
            widget.storyController?.markMediaVisible();
          } else {
            debugPrint(
                'STORY_DEBUG: 👁️ StoryVideo: Video not visible or already marked visible');
          }
        } else {
          debugPrint(
              'STORY_DEBUG: 👁️ StoryVideo: RenderBox not available or no size');
        }
      } else {
        debugPrint(
            'STORY_DEBUG: 👁️ StoryVideo: Not checking visibility - mounted: $mounted, _isVisible: $_isVisible');
      }
    });
  }
}

/**
 * @name VideoContentView
 * @description Stateless widget that shows a video player or loading/error widgets based on video loading state.
 */
class VideoContentView extends StatelessWidget {
  final LoadState videoLoadState;
  final VideoPlayerController? playerController;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  const VideoContentView({
    Key? key,
    required this.videoLoadState,
    required this.playerController,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (videoLoadState == LoadState.success &&
        playerController != null &&
        playerController!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: playerController!.value.aspectRatio,
          child: VideoPlayer(playerController!),
        ),
      );
    }

    if (videoLoadState == LoadState.loading) {
      return Center(
        child: loadingWidget ??
            const SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
      );
    }

    return Center(
      child: errorWidget ??
          const Text(
            "Media failed to load.",
            style: TextStyle(color: Colors.white),
          ),
    );
  }
}
