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
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math_64.dart' as VecMath64;

bool _isPhone() => Platform.isAndroid || Platform.isIOS;

enum CropViewDoubleTapMode { none, quickScale, quickRotate }

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
  Offset? _gestureContentPoint;
  // Scaling point on widget coordinates
  Offset? _gestureLocalPoint;
  double? _rotationRef;
  Offset? _longPressLast;
  CropViewDoubleTapMode doubleTapMode = CropViewDoubleTapMode.none;

  Offset get _localCenter => Offset(_bounds.width / 2, _bounds.height / 2);

  void _setBounds(Size size) {
    if(_bounds != size) {
      _bounds = size;
      _calculateSizes(refresh: false);
    }
  }

  Offset _calculateContentPoint(Offset localPoint) {
    Offset contentOffset = _getTranslation();
    Offset containerPositon = Offset(contentOffset.dx + localPoint.dx, contentOffset.dy + localPoint.dy);
    // Content box position from the center
    Offset contentBoxPositon = Offset(
      (containerPositon.dx - _contentBoxPosition.dx) - (_contentBoxSize.width / 2),
      (containerPositon.dy - _contentBoxPosition.dy) - (_contentBoxSize.height / 2)
    );
    VecMath64.Matrix4 rerotate = VecMath64.Matrix4.rotationZ(-_rotation);
    contentBoxPositon = MatrixUtils.transformPoint(rerotate, contentBoxPositon);
    contentBoxPositon = Offset(
      (contentBoxPositon.dx + _contentSize.width / 2) / _scale!,
      (contentBoxPositon.dy + _contentSize.height / 2) / _scale!
    );
    return contentBoxPositon;
  }

  Offset _calculateContainerPoint(Offset contentPoint) {
    Offset contentPosition = Offset(
      (contentPoint.dx - _originSize.width / 2) * _scale!,
      (contentPoint.dy - _originSize.height / 2) * _scale!
    );
    VecMath64.Matrix4 rotation = VecMath64.Matrix4.rotationZ(_rotation);
    contentPosition = MatrixUtils.transformPoint(rotation, contentPosition);
    return Offset(
      contentPosition.dx + _contentBoxSize.width / 2 + _contentBoxPosition.dx,
      contentPosition.dy + _contentBoxSize.height / 2 + _contentBoxPosition.dy
    );
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
    VecMath64.Matrix4 transform = VecMath64.Matrix4.identity();
    transform.translate(-transX, -transY);
    _transformer.value = transform;
  }

  void _moveToRefPoint() {
    if (_gestureLocalPoint != null && _gestureContentPoint != null) {
      Offset point = _calculateContainerPoint(_gestureContentPoint!);
      _moveContainerPointToLocalPoint(point, _gestureLocalPoint!);
    }
  }

  double _validateScale(double scale) {
    if (scale < _minScale) return _minScale;
    if (scale > _maxScale) return _maxScale;
    return scale;
  }

  double _validateRotation(double value) {
    double circle = (value.abs() / (2 * pi)).floorToDouble();
    if (value < 0) {
      return value + circle * 2 * pi;
    }
    return value - circle * 2 * pi;
  }

  void _calculateScaleBoundary(Rect cropWindow) {
    VecMath64.Matrix4 transform = VecMath64.Matrix4.rotationZ(_rotation);
    Rect contentBox = Rect.fromLTWH(0, 0, _originSize.width, _originSize.height);
    contentBox = MatrixUtils.transformRect(transform, contentBox);
    _minScale = max(cropWindow.width / contentBox.width, cropWindow.height / contentBox.height);
    _maxScale = maxScale * _minScale;
    _scale = _validateScale(_scale ?? 0);
  }

  // Long press
  void _changeRoration(double diff) {
    _rotation = _validateRotation(_rotation + diff);
    _calculateSizes();
    _moveToRefPoint();
  }

  // Scroll (desktop) or 2 fingers (phone)
  void _changeScaleRotation(double scaleDiff, double rotationDiff) {
    if (_scale != null && _scaleRef != null) {
      double scale = _validateScale(_scaleRef! + scaleDiff);
      _scale = scale;
    }
    if (_rotationRef != null) {
      _rotation = _validateRotation(_rotationRef! + rotationDiff);
    }
    _calculateSizes();
    _moveToRefPoint();
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
    VecMath64.Matrix4 transform = VecMath64.Matrix4.identity();
    transform.translate(-translation.dx, -translation.dy);
    _transformer.value = transform;
  }

  void _calculateSizes({bool refresh = true}) {
    final bool shouldMove = _scale == null;
    Rect cropWindow = calculateCropWindow(_bounds);
    _calculateScaleBoundary(cropWindow);
    double scale = _scale!;
    Size oldContentSize = _contentSize;
    _contentSize = Size(_originSize.width * scale, _originSize.height * scale);
    VecMath64.Matrix4 transform = VecMath64.Matrix4.rotationZ(_rotation);
    Rect contentBox = Rect.fromLTWH(0, 0, _contentSize.width, _contentSize.height);
    contentBox = MatrixUtils.transformRect(transform, contentBox);
    Size expectedSize = Size(
      contentBox.width + _bounds.width - cropWindow.size.width,
      contentBox.height + _bounds.height - cropWindow.size.height
    );
    // _contentBoxPosition = cropWindow.topLeft;
    double boxSize = max(max(_contentSize.width, _contentSize.height), max(contentBox.size.width, contentBox.size.height));
    _contentBoxSize = Size(boxSize, boxSize);
    _contentBoxPosition = Offset(
      cropWindow.left - (boxSize - contentBox.width) / 2,
      cropWindow.top - (boxSize - contentBox.height) / 2,
    );
    if (expectedSize != _containerSize || oldContentSize != _contentSize) {
      _containerSize = expectedSize;
      if (refresh) {
        _setState(() {});
      }
    }
    if (shouldMove) {
      double dx = (contentBox.width - cropWindow.width) / 2;
      if (dx < 0) dx = 0;
      double dy = (contentBox.height - cropWindow.height) / 2;
      if (dy < 0) dy = 0;
      VecMath64.Matrix4 transform = VecMath64.Matrix4.identity();
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

  void _gestureStarts(Offset point) {
    _gestureLocalPoint = point;
    _gestureContentPoint = _calculateContentPoint(point);
    _scaleRef = _scale;
    _rotationRef = _rotation;
  }

  void _gestureNotifies(ScaleUpdateDetails details) {
    double scaleDiff = details.scale - 1;
    _changeScaleRotation(scaleDiff, details.rotation);
  }

  void _gestureEnds() {
    _gestureLocalPoint = null;
    _gestureContentPoint = null;
    _scaleRef = null;
    _rotationRef = null;
  }

  void _longPressStart(LongPressStartDetails details) {
    _longPressLast = details.localPosition;
    _gestureStarts(_localCenter);
  }

  void _longPressDrag(LongPressMoveUpdateDetails details) {
    if (_longPressLast == null) return;
    Offset center = _localCenter;
    Offset origin = _longPressLast!;
    Vector2 vec1 = Vector2(origin.dx - center.dx, origin.dy - center.dy);
    Vector2 vec2 = Vector2(details.localPosition.dx - center.dx, details.localPosition.dy - center.dy);
    double angle = atan2(vec1.x * vec2.y - vec1.y * vec2.x, vec1.x * vec2.x + vec1.y * vec2.y);
    _changeRoration(angle);
    _longPressLast = details.localPosition;
  }

  void _longPressEnd(LongPressEndDetails details) {
    _longPressLast = null;
    _gestureEnds();
  }

  void _doubleTapFires(Offset point) {
    switch (doubleTapMode) {
    case CropViewDoubleTapMode.none:
      break;
    case CropViewDoubleTapMode.quickScale:
      _gestureStarts(point);
      if (_scale! < _maxScale) {
        _changeScaleRotation(_maxScale - _scaleRef!, 0);
      } else {
        _changeScaleRotation(_minScale - _scaleRef!, 0);
      }
      _gestureEnds();
    case CropViewDoubleTapMode.quickRotate:
      _gestureStarts(_localCenter);
      double pi2 = pi / 2;
      double round = pi * 2;
      double pi23 = pi * 3 / 2;
      if (_rotation < 0) {
        if (_rotation >= -pi2) {
          _changeRoration(-_rotation);
        } else if (_rotation >= -pi) {
          _changeRoration(-_rotation - pi2);
        } else if (_rotation >= -pi23) {
          _changeRoration(-_rotation - pi);
        } else {
          _changeRoration(-_rotation - pi23);
        }
      } else {
        if (_rotation < pi2) {
          _changeRoration(pi2 - _rotation);
        } else if (_rotation < pi) {
          _changeRoration(pi - _rotation);
        } else if (_rotation < pi23) {
          _changeRoration(pi23 - _rotation);
        } else {
          _changeRoration(round - _rotation);
        }
      }
      _gestureEnds();
    }
  }

  /// Get crop info: (rotation angle (radian), crop frame (after rotation))
  (double, Rect) getCropFrame() {
    Offset translation = _getTranslation();
    Rect cropWindow = calculateCropWindow(_bounds);
    double scale = _scale ?? 1;
    return (_rotation, Rect.fromLTWH(
      (translation.dx / scale).floor().toDouble(),
      (translation.dy / scale).floor().toDouble(),
      (cropWindow.width / scale).floor().toDouble(),
      (cropWindow.height / scale).floor().toDouble()
    ));
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

  Offset? _doubleTapPoint;

  @override
  void initState() {
    super.initState();
    widget.adapter._originSize = Size(widget.originWidth, widget.originHeight);
    widget.adapter._setState = setState;
  }

  bool _validateGesture(int count) => _isPhone() ? count == 2 : count == 0;

  void _gestureOnStart(ScaleStartDetails details) {
    if (!_validateGesture(details.pointerCount)) return;
    widget.adapter._gestureStarts(details.localFocalPoint);
  }

  void _gestureOnNotified(ScaleUpdateDetails details) {
    if (!_validateGesture(details.pointerCount)) return;
    widget.adapter._gestureNotifies(details);
  }

  void _gestureOnEnd(ScaleEndDetails details) {
    if (!_validateGesture(details.pointerCount)) return;
    widget.adapter._gestureEnds();
  }

  void _doubleTapGestureOnDown(TapDownDetails details) {
    _doubleTapPoint = details.localPosition;
  }

  void _doubleTapGestureOnFire() {
    if (_doubleTapPoint != null) widget.adapter._doubleTapFires(_doubleTapPoint!);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      widget.adapter._setBounds(Size(constraint.maxWidth, constraint.maxHeight));
      return Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onDoubleTap: _doubleTapGestureOnFire,
          onDoubleTapDown: _doubleTapGestureOnDown,
          onLongPressStart:(details) => widget.adapter._longPressStart(details),
          onLongPressMoveUpdate: (details) => widget.adapter._longPressDrag(details),
          onLongPressEnd: (details) => widget.adapter._longPressEnd(details),
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
              child: Stack(children: [
                Positioned(
                  top: widget.adapter._contentBoxPosition.dy,
                  left: widget.adapter._contentBoxPosition.dx,
                  width: widget.adapter._contentBoxSize.width,
                  height: widget.adapter._contentBoxSize.height,
                  child: Center(child: Transform.rotate(
                    angle: widget.adapter._rotation,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: widget.adapter._contentSize.width,
                      height: widget.adapter._contentSize.height,
                      child: widget.child
                    )
                  ))
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