part of crop_your_image;

const dotTotalSize = 32.0; // fixed corner dot size.

typedef CornerDotBuilder = Widget Function(
    double size, EdgeAlignment edgeAlignment);

enum CropStatus { nothing, loading, ready, cropping }

/// Widget for the entry point of crop_your_image.
class Crop extends StatelessWidget {
  /// original image data
  final Uint8List image;

  /// original image data
  final bool fixedCroppedArea;
  /// callback when cropping completed
  final ValueChanged<Uint8List> onCropped;

  /// fixed aspect ratio of cropping area.
  /// null, by default, means no fixed aspect ratio.
  final double? aspectRatio;

  /// initial size of cropping area.
  /// Set double value less than 1.0.
  /// if initialSize is 1.0 (or null),
  /// cropping area would expand as much as possible.
  final double? initialSize;

  /// Initial [Rect] of cropping area.
  /// This [Rect] must be based on the rect of [image] data, not screen.
  ///
  /// e.g. If the original image size is 1280x1024,
  /// giving [Rect.fromLTWH(240, 212, 800, 600)] as [initialArea] would
  /// result in covering exact center of the image with 800x600 image size.
  ///
  /// If [initialArea] is given, [initialSize] is ignored.
  /// In other hand, [aspectRatio] is still enabled although initial shape of
  /// cropping area depends on [initialArea]. Once user moves cropping area
  /// with their hand, the shape of cropping area is calculated depending on [aspectRatio].
  final Rect? initialArea;

  /// flag if cropping image with circle shape.
  /// if [true], [aspectRatio] is fixed to 1.
  final bool withCircleUi;

  /// conroller for control crop actions
  final CropController? controller;

  /// Callback called when cropping area moved.
  final ValueChanged<Rect>? onMoved;

  /// Callback called when status of Crop widget is changed.
  ///
  /// note: Currently, the very first callback is [CropStatus.ready]
  /// which is called after loading [image] data for the first time.
  final ValueChanged<CropStatus>? onStatusChanged;

  /// [Color] of the mask widget which is placed over the cropping editor.
  final Color? maskColor;

  /// [Color] of the base color of the cropping editor.
  final Color baseColor;

  /// builder for corner dot widget.
  /// [CornerDotBuilder] passes [size] which indicates the size of each dots
  /// and [EdgeAlignment] which indicates the position of each dots.
  /// If default dot Widget with different color is needed, [DotControl] is available.
  final CornerDotBuilder? cornerDotBuilder;

  const Crop({
    Key? key,
    required this.image,
    required this.onCropped,
    this.aspectRatio,
    this.fixedCroppedArea=false,
    this.initialSize,
    this.initialArea,
    this.withCircleUi = false,
    this.controller,
    this.onMoved,
    this.onStatusChanged,
    this.maskColor,
    this.baseColor = Colors.white,
    this.cornerDotBuilder,
  })  : assert((initialSize ?? 1.0) <= 1.0,
            'initialSize must be less than 1.0, or null meaning not specified.'),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (c, constraints) {
        final newData = MediaQuery.of(c).copyWith(
          size: constraints.biggest,
        );
        return MediaQuery(
          data: newData,
          child: _CropEditor(
            image: image,
            fixedCroppedArea: fixedCroppedArea,
            onCropped: onCropped,
            aspectRatio: aspectRatio,
            initialSize: initialSize,
            initialArea: initialArea,
            withCircleUi: withCircleUi,
            controller: controller,
            onMoved: onMoved,
            onStatusChanged: onStatusChanged,
            maskColor: maskColor,
            baseColor: baseColor,
            cornerDotBuilder: cornerDotBuilder,
          ),
        );
      },
    );
  }
}

class _CropEditor extends StatefulWidget {
  final Uint8List image;
  final ValueChanged<Uint8List> onCropped;
  final double? aspectRatio;
  final double? initialSize;
  final Rect? initialArea;
  final bool withCircleUi;
  final bool fixedCroppedArea;
  final CropController? controller;
  final ValueChanged<Rect>? onMoved;
  final ValueChanged<CropStatus>? onStatusChanged;
  final Color? maskColor;
  final Color baseColor;
  final CornerDotBuilder? cornerDotBuilder;

  const _CropEditor({
    Key? key,
    required this.image,
    required this.onCropped,
    this.aspectRatio,
    this.initialSize,
    this.initialArea,
    this.withCircleUi = false,
    this.fixedCroppedArea = false,
    this.controller,
    this.onMoved,
    this.onStatusChanged,
    this.maskColor,
    required this.baseColor,
    this.cornerDotBuilder,
  }) : super(key: key);

  @override
  _CropEditorState createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late CropController _cropController;
  late Rect _rect;
  image.Image? _targetImage;
  late Rect _imageRect;

  double? _aspectRatio;
  bool _withCircleUi = false;
  bool _isFitVertically = false;
  Future<image.Image?>? _lastComputed;

  bool get _isImageLoading => _lastComputed != null;

  _Calculator get calculator => _isFitVertically
      ? const _VerticalCalculator()
      : const _HorizontalCalculator();

  set rect(Rect newRect) {
    setState(() {
      _rect = newRect;
    });
    widget.onMoved?.call(_rect);
  }

  @override
  void initState() {
    _cropController = widget.controller ?? CropController();
    _cropController.delegate = CropControllerDelegate()
      ..onCrop = _crop
      ..onChangeAspectRatio = (aspectRatio) {
        _resizeWith(aspectRatio, null);
      }
      ..onChangeWithCircleUi = (withCircleUi) {
        _withCircleUi = withCircleUi;
        _resizeWith(null, null);
      }
      ..onImageChanged = _resetImage
      ..onChangeRect = (newRect) {
        rect = calculator.correct(newRect, _imageRect);
      }
      ..onChangeArea = (newArea) {
        _resizeWith(_aspectRatio, newArea);
      };

    super.initState();
  }

  @override
  void didChangeDependencies() {
    final future = compute(_fromByteData, widget.image);
    _lastComputed = future;
    future.then((converted) {
      if (_lastComputed == future) {
        _targetImage = converted;
        _withCircleUi = widget.withCircleUi;
        _resetCroppingArea();

        setState(() {
          _lastComputed = null;
        });
        widget.onStatusChanged?.call(CropStatus.ready);
      }
    });
    super.didChangeDependencies();
  }

  /// reset image to be cropped
  void _resetImage(Uint8List targetImage) {
    widget.onStatusChanged?.call(CropStatus.loading);
    final future = compute(_fromByteData, targetImage);
    _lastComputed = future;
    future.then((converted) {
      if (_lastComputed == future) {
        setState(() {
          _targetImage = converted;
          _lastComputed = null;
        });
        _resetCroppingArea();
        widget.onStatusChanged?.call(CropStatus.ready);
      }
    });
  }

  /// reset [Rect] of cropping area with current state
  void _resetCroppingArea() {
    final screenSize = MediaQuery.of(context).size;

    final imageRatio = _targetImage!.width / _targetImage!.height;
    _isFitVertically = imageRatio < screenSize.aspectRatio;

    _imageRect = calculator.imageRect(screenSize, imageRatio);

    _resizeWith(widget.aspectRatio, widget.initialArea);
  }

  /// resize cropping area with given aspect ratio.
  void _resizeWith(double? aspectRatio, Rect? initialArea) {
    _aspectRatio = _withCircleUi ? 1 : aspectRatio;

    if (initialArea == null) {
      rect = calculator.initialCropRect(
        MediaQuery.of(context).size,
        _imageRect,
        _aspectRatio ?? 1,
        widget.initialSize ?? 1,
      );
    } else {
      final screenSizeRatio = calculator.screenSizeRatio(
        _targetImage!,
        MediaQuery.of(context).size,
      );
      rect = Rect.fromLTWH(
        _imageRect.left + initialArea.left / screenSizeRatio,
        _imageRect.top + initialArea.top / screenSizeRatio,
        initialArea.width / screenSizeRatio,
        initialArea.height / screenSizeRatio,
      );
    }
  }

  /// crop given image with given area.
  Future<void> _crop(bool withCircleShape) async {
    assert(_targetImage != null);

    final screenSizeRatio = calculator.screenSizeRatio(
      _targetImage!,
      MediaQuery.of(context).size,
    );

    widget.onStatusChanged?.call(CropStatus.cropping);

    // use compute() not to block UI update
    final cropResult = await compute(
      withCircleShape ? _doCropCircle : _doCrop,
      [
        _targetImage!,
        Rect.fromLTWH(
          (_rect.left - _imageRect.left) * screenSizeRatio,
          (_rect.top - _imageRect.top) * screenSizeRatio,
          _rect.width * screenSizeRatio,
          _rect.height * screenSizeRatio,
        ),
      ],
    );
    widget.onCropped(cropResult);

    widget.onStatusChanged?.call(CropStatus.ready);
  }

  @override
  Widget build(BuildContext context) {
    return _isImageLoading
        ? Center(child: const CircularProgressIndicator())
        : Stack(
            children: [
              Container(
                color: widget.baseColor,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Image.memory(
                  widget.image,
                  fit: _isFitVertically ? BoxFit.fitHeight : BoxFit.fitWidth,
                ),
              ),
              IgnorePointer(
                child: ClipPath(
                  clipper: _withCircleUi
                      ? _CircleCropAreaClipper(_rect)
                      : _CropAreaClipper(_rect),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: widget.maskColor ?? Colors.black.withAlpha(100),
                  ),
                ),
              ),
              Positioned(
                left: _rect.left,
                top: _rect.top,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    rect = calculator.moveRect(
                      _rect,
                      details.delta.dx,
                      details.delta.dy,
                      _imageRect,
                    );
                  },
                  child: Container(
                    width: _rect.width,
                    height: _rect.height,
                    color: Colors.transparent,
                  ),
                ),
              ),
              Positioned(
                left: _rect.left - (dotTotalSize / 2),
                top: _rect.top - (dotTotalSize / 2),
                child: IgnorePointer(
                  ignoring: widget.fixedCroppedArea,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      rect = calculator.moveTopLeft(
                        _rect,
                        details.delta.dx,
                        details.delta.dy,
                        _imageRect,
                        _aspectRatio,
                      );
                    },
                    child: widget.cornerDotBuilder
                            ?.call(dotTotalSize, EdgeAlignment.topLeft) ??
                        const DotControl(),
                  ),
                ),
              ),
              Positioned(
                left: _rect.right - (dotTotalSize / 2),
                top: _rect.top - (dotTotalSize / 2),
                child: IgnorePointer(
                  ignoring: widget.fixedCroppedArea,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      rect = calculator.moveTopRight(
                        _rect,
                        details.delta.dx,
                        details.delta.dy,
                        _imageRect,
                        _aspectRatio,
                      );
                    },
                    child: widget.cornerDotBuilder
                            ?.call(dotTotalSize, EdgeAlignment.topRight) ??
                        const DotControl(),
                  ),
                ),
              ),
              Positioned(
                left: _rect.left - (dotTotalSize / 2),
                top: _rect.bottom - (dotTotalSize / 2),
                child: IgnorePointer(
                  ignoring: widget.fixedCroppedArea,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      rect = calculator.moveBottomLeft(
                        _rect,
                        details.delta.dx,
                        details.delta.dy,
                        _imageRect,
                        _aspectRatio,
                      );
                    },
                    child: widget.cornerDotBuilder
                            ?.call(dotTotalSize, EdgeAlignment.bottomLeft) ??
                        const DotControl(),
                  ),
                ),
              ),
              Positioned(
                left: _rect.right - (dotTotalSize / 2),
                top: _rect.bottom - (dotTotalSize / 2),
                child: IgnorePointer(
                  ignoring: widget.fixedCroppedArea,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      rect = calculator.moveBottomRight(
                        _rect,
                        details.delta.dx,
                        details.delta.dy,
                        _imageRect,
                        _aspectRatio,
                      );
                    },
                    child: widget.cornerDotBuilder
                            ?.call(dotTotalSize, EdgeAlignment.bottomRight) ??
                        const DotControl(),
                  ),
                ),
              ),
            ],
          );
  }
}

class _CropAreaClipper extends CustomClipper<Path> {
  final Rect rect;

  _CropAreaClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addPath(
        Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close(),
        Offset.zero,
      )
      ..addRect(Rect.fromLTWH(0.0, 0.0, size.width, size.height))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}

class _CircleCropAreaClipper extends CustomClipper<Path> {
  final Rect rect;

  _CircleCropAreaClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addOval(Rect.fromCircle(center: rect.center, radius: rect.width / 2))
      ..addRect(Rect.fromLTWH(0.0, 0.0, size.width, size.height))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}

/// Defalt dot widget placed on corners to control cropping area.
/// This Widget automaticall fits the appropriate size.
class DotControl extends StatelessWidget {
  const DotControl({
    Key? key,
    this.color = Colors.white,
    this.padding = 8,
  }) : super(key: key);

  /// [Color] of this widget. [Colors.white] by default.
  final Color color;

  /// The size of transparent padding which exists to make dot easier to touch.
  /// Though total size of this widget cannot be changed,
  /// but visible size can be changed by setting this value.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      width: dotTotalSize,
      height: dotTotalSize,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(dotTotalSize),
          child: Container(
            width: dotTotalSize - (padding * 2),
            height: dotTotalSize - (padding * 2),
            color: color,
          ),
        ),
      ),
    );
  }
}

/// process cropping image.
/// this method is supposed to be called only via compute()
Uint8List _doCrop(List<dynamic> cropData) {
  final originalImage = cropData[0] as image.Image;
  final rect = cropData[1] as Rect;
  return Uint8List.fromList(
    image.encodePng(
      image.copyCrop(
        originalImage,
        rect.left.toInt(),
        rect.top.toInt(),
        rect.width.toInt(),
        rect.height.toInt(),
      ),
    ),
  );
}

/// process cropping image with circle shape.
/// this method is supposed to be called only via compute()
Uint8List _doCropCircle(List<dynamic> cropData) {
  final originalImage = cropData[0] as image.Image;
  final rect = cropData[1] as Rect;
  return Uint8List.fromList(
    image.encodePng(
      image.copyCropCircle(
        originalImage,
        center:
            image.Point(rect.left + rect.width / 2, rect.top + rect.height / 2),
        radius: min(rect.width, rect.height) ~/ 2,
      ),
    ),
  );
}

// decode orientation awared Image.
image.Image _fromByteData(Uint8List data) {
  final tempImage = image.decodeImage(data);
  assert(tempImage != null);

  // check orientation
  switch (tempImage?.exif.data[0x0112] ?? -1) {
    case 3:
      return image.copyRotate(tempImage!, 180);
    case 6:
      return image.copyRotate(tempImage!, 90);
    case 8:
      return image.copyRotate(tempImage!, -90);
  }
  return tempImage!;
}
