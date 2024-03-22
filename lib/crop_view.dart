/*
MIT License

Copyright © 2024 DươngPQ

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

library crop_view;

import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' as VecMath64;

bool _isPhone() => Platform.isAndroid || Platform.isIOS;

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
  Offset _contentBoxPosition = Offset.zero;
  Size _contentBoxSize = Size.zero;
  // Tracking data
  double? _scale;
  double _rotation = 0;
  double _minScale = 0.1;
  double _maxScale = 5;
  double? _scaleRef;
  // Scaling point at original coordinates
  Offset? _scalingPoint;
  // Scaling point on widget coordinates
  Offset? _scalingRefPoint;
  double? _rotationRef;
  Offset? _rotationPoint;
  Offset? _rotationRefPoint;

  void _setBounds(Size size) {
    if(_bounds != size) {
      _bounds = size;
      _calculateSizes(refresh: false);
    }
  }

  Offset _calculateContentPoint(Offset localPoint) {
    Offset contentOffset = _getTranslation();
    Offset containerPositon = Offset(contentOffset.dx + localPoint.dx, contentOffset.dy + localPoint.dy);
    return Offset(
      (containerPositon.dx - _contentBoxPosition.dx) / _scale!,
      (containerPositon.dy - _contentBoxPosition.dy) / _scale!
    );
  }

  Offset _calculateContainerPoint(Offset contentPoint) {
    Offset contentPosition = Offset(contentPoint.dx * _scale!, contentPoint.dy * _scale!);
    return Offset(contentPosition.dx + _contentBoxPosition.dx, contentPosition.dy + _contentBoxPosition.dy);
  }

  void _moveContainerPointToLocalPoint(Offset containerPoint, Offset localPoint) {
    double transX = max(containerPoint.dx - localPoint.dx, 0);
    if (transX + _bounds.width > _containerSize.width) {
      transX = _containerSize.width - _bounds.width;
    }
    double transY = max(containerPoint.dy - localPoint.dy, 0);
    if (transY + _bounds.height > _containerSize.height) {
      transY = _containerSize.height - _bounds.height;
    }
    Matrix4 transform = Matrix4.identity();
    transform.translate(-transX, -transY);
    _transformer.value = transform;
  }

  void _startRotate(Offset point) {
    _rotationRef = _rotation;
    _rotationRefPoint = point;
    _rotationPoint = _calculateContentPoint(point);
  }

  void _startScale(Offset point) {
    _scaleRef = _scale;
    _scalingRefPoint = point;
    _scalingPoint = _calculateContentPoint(point);
  }

  void _endRotate() {
    _rotationRef = null;
    _rotationPoint = null;
    _rotationRefPoint = null;
  }

  void _endScale() {
    _scaleRef = null;
    _scalingPoint = null;
    _scalingRefPoint = null;
  }

  double _validateScale(double scale) {
    if (scale < _minScale) return _minScale;
    if (scale > _maxScale) return _maxScale;
    return scale;
  }

  void _calculateScaleBoundary(Rect cropWindow) {
    _minScale = max(cropWindow.width / _originSize.width, cropWindow.height / _originSize.height);
    _maxScale = maxScale * _minScale;
    _scale = _validateScale(_scale ?? 0);
  }

  void _changeScale(double diff) {
    if (_scale == null || _scaleRef == null) return;
    double scale = _validateScale(_scaleRef! + diff);
    _scale = scale;
    _calculateSizes();
    if (_scalingPoint != null && _scalingRefPoint != null) {
      Offset point = _calculateContainerPoint(_scalingPoint!);
      _moveContainerPointToLocalPoint(point, _scalingRefPoint!);
    }
  }

  void _changeRoration(double diff) {
    if (_rotationRef == null) return;
    _rotation = _rotationRef! + diff;
    _calculateSizes();
  }

  void _changeScaleRotation(double scaleDiff, double rotationDiff) {

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
    _contentBoxPosition = cropWindow.topLeft;
    _contentBoxSize = _contentSize;
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
    VecMath64.Vector3 translation = _transformer.value.getTranslation();
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
  final bool doubleTapEnable;

  const CropView({
    super.key,
    required this.child,
    required this.mask,
    required this.adapter,
    required this.originWidth,
    required this.originHeight,
    this.doubleTapEnable = true
  });

  @override
  State<StatefulWidget> createState() => _CropViewState();

}

class _CropViewState extends State<CropView> {

  bool _isRotating = false;

  @override
  void initState() {
    super.initState();
    widget.adapter._originSize = Size(widget.originWidth, widget.originHeight);
    widget.adapter._setState = setState;
  }

  bool _isZooming(int count) => _isPhone() ? count == 2 : count == 0;

  void _gestureOnStart(ScaleStartDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    widget.adapter._startScale(details.localFocalPoint);
    if (_isPhone()) {
      widget.adapter._startRotate(details.localFocalPoint);
      _isRotating = true;
    }
  }

  void _gestureOnNotified(ScaleUpdateDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    double scaleDiff = details.scale - 1;
    if (_isPhone()) {
      widget.adapter._changeScaleRotation(scaleDiff, details.rotation);
    } else {
      if (_isRotating) {
        widget.adapter._changeRoration(scaleDiff);
      } else {
        widget.adapter._changeScale(scaleDiff);
      }
    }
  }

  void _gestureOnEnd(ScaleEndDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    widget.adapter._endScale();
    if (_isPhone()) {
      widget.adapter._endRotate();
      _isRotating = false;
    }
  }

  void _tapOnDown(TapDownDetails details) {
    if (!_isPhone()) {
      _isRotating = true;
      widget.adapter._startRotate(details.localPosition);
    }
  }

  void _tapOnUp(TapUpDetails details) {
    if (!_isPhone()) {
      _isRotating = false;
      widget.adapter._endRotate();
    }
  }

  void _doubleTapGestureOnDown(TapDownDetails details) {
    widget.adapter._startScale(details.localPosition);
  }

  void _doubleTapGestureOnFire() {
    if (!widget.doubleTapEnable || widget.adapter._scale == null) return;
    if (widget.adapter._scale! < widget.adapter._maxScale) {
      widget.adapter._changeScale(widget.adapter._maxScale - widget.adapter._scale!);
    } else {
      widget.adapter._changeScale(widget.adapter._minScale - widget.adapter._scale!);
    }
    widget.adapter._endScale();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      widget.adapter._setBounds(Size(constraint.maxWidth, constraint.maxHeight));
      return Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onDoubleTap: _doubleTapGestureOnFire,
          onDoubleTapDown: _doubleTapGestureOnDown,
          onTapDown: _tapOnDown,
          onTapUp: _tapOnUp,
          child: InteractiveViewer(
            constrained: false,
            minScale: 1,
            maxScale: 1,
            transformationController: widget.adapter._transformer,
            onInteractionStart: _gestureOnStart,
            onInteractionUpdate: _gestureOnNotified,
            onInteractionEnd: _gestureOnEnd,
            child: SizedBox(
              width: widget.adapter._containerSize.width,
              height: widget.adapter._containerSize.height,
              child: Stack(fit: StackFit.expand, children: [
                Positioned(
                  top: widget.adapter._contentBoxPosition.dy,
                  left: widget.adapter._contentBoxPosition.dx,
                  width: widget.adapter._contentBoxSize.width,
                  height: widget.adapter._contentBoxSize.height,
                  child: Transform.rotate(
                    angle: widget.adapter._rotation,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: widget.adapter._contentSize.width,
                      height: widget.adapter._contentSize.height,
                      child: widget.child
                    ),
                  )
                )
              ])
            )
          )
        ),
        IgnorePointer(child: widget.mask)
      ]);
    });
  }

}