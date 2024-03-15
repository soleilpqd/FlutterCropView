library crop_view;

import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' as VecMath64;

class CropViewAdapter {

  void Function(VoidCallback func) _setState = (_) {};
  final TransformationController _transformer = TransformationController();

  /// How many times of crop window size that user can zoom in.
  final double maxScale;
  /// Function to determine the crop window position with given displaying area [bounds]
  final Rect Function(Size bounds) calculateCropWindow;
  /// Constructor
  CropViewAdapter({this.maxScale = 5, required this.calculateCropWindow});

  // Base data
  Size _originSize = Size.zero;
  Size _bounds = Size.zero;
  // Data need to be calculated
  Size _contentSize = Size.zero;
  Size _containerSize = Size.zero;
  Offset _contentPosition = Offset.zero;
  // Tracking data
  double? _scale;
  double _minScale = 0.1;
  double _maxScale = 5;

  void _setBounds(Size size) {
    if(_bounds != size) {
      _bounds = size;
      _calculateSizes(refresh: false);
    }
  }

  double _validateScale(double scale) {
    if (scale < _minScale) scale = _minScale;
    if (scale > _maxScale) scale = _maxScale;
    return scale;
  }

  void _calculateScaleBoundary(Rect cropWindow) {
    _minScale = max(cropWindow.width / _originSize.width, cropWindow.height / _originSize.height);
    _maxScale = maxScale * _minScale;
    _scale = _validateScale(_scale ?? 0);
  }

  void _changeScale(double diff) {
    if (_scale == null) return;
    double scale = _validateScale((_scale ?? 1) + diff);
    if (_scale != scale) {
      _scale = scale;
      _calculateSizes();
    }
  }

  void _validateTranslation() {
    Offset translation = _getTranslation();
    double dx = translation.dx + _bounds.width;
    double dy = translation.dy + _bounds.height;
    bool isInvalid = false;
    if (dx > _containerSize.width) {
      dx -= _containerSize.width;
      isInvalid = true;
    } else {
      dx = 0;
    }
    if (dy > _containerSize.height) {
      dy -= _containerSize.height;
      isInvalid = true;
    } else {
      dy = 0;
    }
    if (!isInvalid) return;
    translation = Offset(translation.dx - dx, translation.dy - dy);
    Matrix4 transform = Matrix4.identity();
    transform.translate(-translation.dx, -translation.dy);
    _transformer.value = transform;
  }

  void _calculateSizes({bool refresh = true}) {
    final bool shouldMove = _scale == null;
    Rect cropWindow = calculateCropWindow(_bounds);
    _calculateScaleBoundary(cropWindow);
    double scale = _scale ?? 1;
    Size oldContentSize = _contentSize;
    _contentSize = Size(_originSize.width * scale, _originSize.height * scale);
    Size expectedSize = Size(
      _contentSize.width + _bounds.width - cropWindow.size.width,
      _contentSize.height + _bounds.height - cropWindow.size.height
    );
    _contentPosition = cropWindow.topLeft;
    if (expectedSize != _containerSize || oldContentSize != _contentSize) {
      _containerSize = expectedSize;
      if (refresh) {
        _setState(() {});
      }
    }
    if (shouldMove) {
      double dx = (_contentSize.width - cropWindow.width) / 2;
      if (dx < 0) dx = 0;
      double dy = (_contentSize.height - cropWindow.height) / 2;
      if (dy < 0) dy = 0;
      Matrix4 transform = Matrix4.identity();
      transform.translate(-dx, -dy);
      _transformer.value = transform;
    } else {
      _validateTranslation();
    }
  }

  Offset _getTranslation() {
    VecMath64.Vector3 translation = VecMath64.Vector3.zero();
    VecMath64.Quaternion rotation = VecMath64.Quaternion.identity();
    VecMath64.Vector3 scale = VecMath64.Vector3.zero();
    _transformer.value.decompose(translation, rotation, scale);
    return Offset(max(0, -translation.x), max(0, -translation.y));
  }

  Rect getCropFrame() {
    Offset translation = _getTranslation();
    Rect cropWindow = calculateCropWindow(_bounds);
    double scale = _scale ?? 1;
    return Rect.fromLTWH(
      (translation.dx / scale).floor().toDouble(),
      (translation.dy / scale).floor().toDouble(),
      (cropWindow.width / scale).floor().toDouble(),
      (cropWindow.height / scale).floor().toDouble()
    );
  }

}

class CropView extends StatefulWidget {

  /// Mask view
  final Widget mask;
  /// Child widget (target widget to crop on).
  /// Simple example: `widgets.FittedBox(child: widgets.Image())`.
  final Widget child;
  /// Object to track and return result
  final CropViewAdapter adapter;
  /// Original width (simple words: image width)
  final double originWidth;
  /// Original width (simple words: image height)
  final double originHeight;

  const CropView({
    super.key,
    required this.child,
    required this.mask,
    required this.adapter,
    required this.originWidth,
    required this.originHeight
  });

  @override
  State<StatefulWidget> createState() => _CropViewState();

}

class _CropViewState extends State<CropView> {

  @override
  void initState() {
    super.initState();
    widget.adapter._originSize = Size(widget.originWidth, widget.originHeight);
    widget.adapter._setState = setState;
  }

  void _gestureOnNotified(ScaleUpdateDetails details) {
    double scaleDiff = details.scale - 1;
    widget.adapter._changeScale(scaleDiff);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      widget.adapter._setBounds(Size(constraint.maxWidth, constraint.maxHeight));
      return Stack(fit: StackFit.expand, children: [
        InteractiveViewer(
          constrained: false,
          minScale: 1,
          maxScale: 1,
          transformationController: widget.adapter._transformer,
          onInteractionUpdate: _gestureOnNotified,
          child: SizedBox(
            width: widget.adapter._containerSize.width,
            height: widget.adapter._containerSize.height,
            child: Stack(fit: StackFit.expand, children: [
              Positioned(
                top: widget.adapter._contentPosition.dy,
                left: widget.adapter._contentPosition.dx,
                width: widget.adapter._contentSize.width,
                height: widget.adapter._contentSize.height,
                child: widget.child
              )
            ])
          )
        ),
        IgnorePointer(child: widget.mask)
      ]);
    });
  }

}