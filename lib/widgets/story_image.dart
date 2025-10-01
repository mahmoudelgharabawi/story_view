import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils.dart';
import '../controller/story_controller.dart';

/// Utitlity to load image (gif, png, jpg, etc) media just once. Resource is
/// cached to disk with default configurations of [DefaultCacheManager].
class ImageLoader {
  ui.Codec? frames;

  String url;

  Map<String, dynamic>? requestHeaders;

  LoadState state = LoadState.loading; // by default

  ImageLoader(this.url, {this.requestHeaders});

  /// Load image from disk cache first, if not found then load from network.
  /// `onComplete` is called when [imageBytes] become available.
  void loadImage(VoidCallback onComplete) {
    debugPrint(
        'STORY_DEBUG_V1: 🖼️ ImageLoader: loadImage() called for URL: $url');
    if (this.frames != null) {
      debugPrint(
          'STORY_DEBUG: 🖼️ ImageLoader: Frames already available, marking as success');
      this.state = LoadState.success;
      onComplete();
      return;
    }

    // Ensure we start with loading state
    this.state = LoadState.loading;
    debugPrint(
        'STORY_DEBUG: 🖼️ ImageLoader: Starting to load from cache/network...');

    final fileStream = DefaultCacheManager().getFileStream(this.url,
        headers: this.requestHeaders as Map<String, String>?);

    fileStream.listen(
      (fileResponse) {
        debugPrint(
            'STORY_DEBUG_V1: 🖼️ ImageLoader: File stream response received');
        if (!(fileResponse is FileInfo)) {
          debugPrint(
              'STORY_DEBUG_V1: 🖼️ ImageLoader: Not a FileInfo, ignoring');
          return;
        }
        // the reason for this is that, when the cache manager fetches
        // the image again from network, the provided `onComplete` should
        // not be called again
        if (this.frames != null) {
          debugPrint(
              '🖼️ ImageLoader: Frames already set, ignoring duplicate response');
          return;
        }

        try {
          debugPrint(
              'STORY_DEBUG: 🖼️ ImageLoader: Reading image bytes from file...');
          final imageBytes = fileResponse.file.readAsBytesSync();
          debugPrint(
              '🖼️ ImageLoader: Image bytes read, size: ${imageBytes.length} bytes');

          ui.instantiateImageCodec(imageBytes).then((codec) {
            debugPrint(
                'STORY_DEBUG: 🖼️ ImageLoader: Image codec instantiated successfully');
            this.frames = codec;
            this.state = LoadState.success;
            onComplete();
          }, onError: (error) {
            debugPrint(
                'STORY_DEBUG: 🖼️ ImageLoader: Failed to instantiate image codec: $error');
            this.state = LoadState.failure;
            onComplete();
          });
        } catch (e) {
          debugPrint(
              'STORY_DEBUG: 🖼️ ImageLoader: Exception while reading image bytes: $e');
          this.state = LoadState.failure;
          onComplete();
        }
      },
      onError: (error) {
        debugPrint(
            'STORY_DEBUG_V1: 🖼️ ImageLoader: Error in file stream: $error');
        this.state = LoadState.failure;
        onComplete();
      },
    );
  }
}

/// Widget to display animated gifs or still images. Shows a loader while image
/// is being loaded. Listens to playback states from [controller] to pause and
/// forward animated media.
class StoryImage extends StatefulWidget {
  final ImageLoader imageLoader;

  final BoxFit? fit;

  final StoryController? controller;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryImage(
    this.imageLoader, {
    Key? key,
    this.controller,
    this.fit,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key ?? UniqueKey());

  /// Use this shorthand to fetch images/gifs from the provided [url]
  factory StoryImage.url(
    String url, {
    StoryController? controller,
    Map<String, dynamic>? requestHeaders,
    BoxFit fit = BoxFit.fitWidth,
    Widget? loadingWidget,
    Widget? errorWidget,
    Key? key,
  }) {
    return StoryImage(
      ImageLoader(
        url,
        requestHeaders: requestHeaders,
      ),
      controller: controller,
      fit: fit,
      loadingWidget: loadingWidget,
      errorWidget: errorWidget,
      key: key,
    );
  }

  @override
  State<StatefulWidget> createState() => StoryImageState();
}

class StoryImageState extends State<StoryImage> with WidgetsBindingObserver {
  ui.Image? currentFrame;

  Timer? _timer;

  StreamSubscription<PlaybackState>? _streamSubscription;

  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🖼️ StoryImage: initState() called for URL: ${widget.imageLoader.url}');

    // Add observer for visibility changes
    WidgetsBinding.instance.addObserver(this);

    // Always start loading - this will pause the controller
    widget.controller?.startLoading();

    if (widget.controller != null) {
      this._streamSubscription =
          widget.controller!.playbackNotifier.listen((playbackState) {
        debugPrint(
            'STORY_DEBUG: 🖼️ StoryImage: PlaybackState changed to: $playbackState');
        // for the case of gifs we need to pause/play
        if (widget.imageLoader.frames == null) {
          debugPrint(
              '🖼️ StoryImage: No frames available yet, ignoring playback state');
          return;
        }

        if (playbackState == PlaybackState.pause) {
          debugPrint('STORY_DEBUG_V1: 🖼️ StoryImage: Pausing animation');
          this._timer?.cancel();
        } else {
          debugPrint('STORY_DEBUG_V1: 🖼️ StoryImage: Starting animation');
          forward();
        }
      });
    }

    debugPrint('STORY_DEBUG_V1: 🖼️ StoryImage: Starting to load image...');
    widget.imageLoader.loadImage(() async {
      debugPrint(
          '🖼️ StoryImage: loadImage callback triggered - state: ${widget.imageLoader.state}');
      if (mounted) {
        if (widget.imageLoader.state == LoadState.success) {
          debugPrint(
              'STORY_DEBUG_V1: 🖼️ StoryImage: Image loaded successfully, finishing loading');
          // Mark loading as finished
          widget.controller?.finishLoading();
          // Check visibility after image is loaded
          _checkVisibility();

          // Fallback: if visibility detection fails, mark as visible after a delay
          Future.delayed(Duration(milliseconds: 200), () {
            if (mounted && !_isVisible) {
              debugPrint(
                  'STORY_DEBUG: 👁️ StoryImage: Fallback - marking image as visible');
              _isVisible = true;
              widget.controller?.markMediaVisible();
            }
          });
        } else {
          debugPrint(
              'STORY_DEBUG_V1: 🖼️ StoryImage: Image loading failed, finishing loading anyway');
          // If loading failed, still finish loading to show error state
          widget.controller?.finishLoading();
          // Check visibility even if loading failed
          _checkVisibility();
          // refresh to show error
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        'STORY_DEBUG: 👁️ StoryImage: _checkVisibility() called - mounted: $mounted, _isVisible: $_isVisible');
    if (!mounted) return;

    // Use a post-frame callback to ensure the widget is fully rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          'STORY_DEBUG: 👁️ StoryImage: Post-frame callback executing - mounted: $mounted, _isVisible: $_isVisible');
      if (mounted && !_isVisible) {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        debugPrint(
            'STORY_DEBUG: 👁️ StoryImage: RenderBox found: ${renderBox != null}, hasSize: ${renderBox?.hasSize}');
        if (renderBox != null && renderBox.hasSize) {
          final position = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          final screenSize = MediaQuery.of(context).size;

          debugPrint(
              'STORY_DEBUG: 👁️ StoryImage: Position: $position, Size: $size, ScreenSize: $screenSize');

          // Check if the widget is visible on screen
          final isVisible = position.dx < screenSize.width &&
              position.dy < screenSize.height &&
              position.dx + size.width > 0 &&
              position.dy + size.height > 0;

          debugPrint(
              'STORY_DEBUG: 👁️ StoryImage: Calculated isVisible: $isVisible');

          if (isVisible && !_isVisible) {
            _isVisible = true;
            debugPrint(
                'STORY_DEBUG: 👁️ StoryImage: Image is now visible on screen');
            widget.controller?.markMediaVisible();
          } else {
            debugPrint(
                'STORY_DEBUG: 👁️ StoryImage: Image not visible or already marked visible');
          }
        } else {
          debugPrint(
              'STORY_DEBUG: 👁️ StoryImage: RenderBox not available or no size');
        }
      } else {
        debugPrint(
            'STORY_DEBUG: 👁️ StoryImage: Not checking visibility - mounted: $mounted, _isVisible: $_isVisible');
      }
    });
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  void forward() async {
    this._timer?.cancel();

    if (widget.controller != null &&
        widget.controller!.playbackNotifier.stream.value ==
            PlaybackState.pause) {
      return;
    }

    final nextFrame = await widget.imageLoader.frames!.getNextFrame();

    this.currentFrame = nextFrame.image;

    if (nextFrame.duration > Duration(milliseconds: 0)) {
      this._timer = Timer(nextFrame.duration, forward);
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Check visibility when the widget is built and image is ready
    if (widget.imageLoader.state == LoadState.success && !_isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkVisibility();
        }
      });
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      child: ImageContentView(
        imageLoader: widget.imageLoader,
        fit: widget.fit,
        currentFrame: this.currentFrame,
        loadingWidget: widget.loadingWidget,
        errorWidget: widget.errorWidget,
      ),
    );
  }
}

/**
 * @name ImageContentView
 * @description Stateless widget that displays an image based on loading state: success, failure, or loading.
 */
class ImageContentView extends StatelessWidget {
  final ImageLoader imageLoader;
  final BoxFit? fit;
  final ui.Image? currentFrame;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  const ImageContentView({
    Key? key,
    required this.imageLoader,
    required this.fit,
    required this.currentFrame,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    switch (imageLoader.state) {
      case LoadState.success:
        return RawImage(
          image: currentFrame,
          fit: fit,
        );
      case LoadState.failure:
        return Center(
          child: errorWidget ??
              const Text(
                "Image failed to load.",
                style: TextStyle(color: Colors.white),
              ),
        );
      default:
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
  }
}
