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

bool isPhone() {
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (error) {
    return false;
  }
}

enum CropViewDoubleTapMode { none, quickScale, quickRotate }

/*
Layout of crop view

+-ScrollView (InteractiveViewer)----------------------+
|+-Container view (SizedBox)-------------------------+|
||                                                   ||
||  +-Content Box (Stack > Positioned > Center)---+  ||
||  |                                             |  ||
||  | +-Content view (SizedBox)-----------------+ |  ||
||  | | <target view>                           | |  ||
||  | +-----------------------------------------+ |  ||
||  |                                             |  ||
||  +---------------------------------------------+  ||
||                                                   ||
|+---------------------------------------------------+|
+-----------------------------------------------------+

- Content View is at the center of Content Box. Size of Content View is Original Size * current scale level.
- Size of Content Box is the maximum dimension of boundary of Content View at current scale level and rotation angle.
- Size of Container View and position of Content Box depend on the crop window (so user can not scroll/drag the Content View outsize the crop window).
(that why we zoom by manualy setting the size of Content View instead of using scaling feature of InteractiveViewer).
*/

class CropViewAdapter {

  void Function(VoidCallback func) _setState = (_) {};
  final TransformationController _transformer = TransformationController();

  /// How many times of crop window size that user can zoom in.
  final double maxScale;
  /// Function to determine the crop window position with given displaying area [bounds].
  final Rect Function(Size bounds) calculateCropWindow;
  /// Constructor
  CropViewAdapter({this.maxScale = 5, required this.calculateCropWindow, this.doubleTapMode = CropViewDoubleTapMode.quickScale});

  // Base data
  /// Original size of target view.
  Size _originSize = Size.zero;
  /// Current size of this view.
  Size _bounds = Size.zero;
  // Data need to be calculated
  /// Size of Content View.
  Size _contentSize = Size.zero;
  /// Size of Container View.
  Size _containerSize = Size.zero;
  /// Positon of Content Box.
  Offset _contentBoxPosition = Offset.zero;
  /// Size of Content Box.
  Size _contentBoxSize = Size.zero;
  // Tracking data.
  /// Current zoom level.
  double? _scale;
  /// Current rotation angle.
  double _rotation = 0;
  /// Minimum value for _scale; depending on `_originSize`, current `_bounds` and crop window.
  double _minScale = 0.1;
  /// Maximum value for _scale; depending on crop window, `_originSize` and `maxScale`.
  double _maxScale = 5;
  /// Scale reference (value of `_scale` when user starts the pinch/stretch gesture).
  double? _scaleRef;
  /// Scaling reference point (point when user starts the gesture) at original coordinates.
  Offset? _gestureContentPoint;
  /// Scaling reference point (point when user starts the gesture) on widget coordinates.
  Offset? _gestureLocalPoint;
  /// Rotation angle reference (value of `_rotation` when user start rotating using 2 fingers).
  double? _rotationRef;
  /// Last updated poinf of long press gesture (use this to calculate the changing angle).
  Offset? _longPressLast;
  /// Scale reference (value of `_scale`) when user starts to rotate by long press.
  double? _rotationRefScale;

  CropViewDoubleTapMode doubleTapMode = CropViewDoubleTapMode.none;

  Offset get _localCenter => Offset(_bounds.width / 2, _bounds.height / 2);

  void _setBounds(Size size) {
    if(_bounds != size) {
      Offset? refPoint;
      if (_scale != null) refPoint = _calculateContentPoint(_localCenter);
      _bounds = size;
      _calculateSizes(refresh: false);
      _moveToRefPoint(_localCenter, refPoint);
    }
  }

  // Calculate location on Target View coordinates (Content View without scale or rotate) from point on widget coordinate
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

  // Calculate location on Container View coordinates from point on Target View coordinates (Content View without scale or rotate)
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

  // Set Content Box positon to move the point on Container View to the point on widget as close as posible
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

  // After some actions (eg. rotate or zoom), content view position may change.
  // So we should move the reference point on target view back to the reference poin on widget.
  void _moveToRefPoint(Offset? localRefPoint, Offset? contentRefPoint) {
    if (localRefPoint != null && contentRefPoint != null) {
      Offset point = _calculateContainerPoint(contentRefPoint);
      _moveContainerPointToLocalPoint(point, localRefPoint);
    }
  }

  // Limit value of `_scale`
  double _validateScale(double scale) {
    if (scale < _minScale) return _minScale;
    if (scale > _maxScale) return _maxScale;
    return scale;
  }

  // Optimize value of angle
  double _validateRotation(double value) {
    double circle = (value.abs() / (2 * pi)).floorToDouble();
    if (value < 0) {
      return value + circle * 2 * pi;
    }
    return value - circle * 2 * pi;
  }

  // Calculate values of `_minScale` and `_maxScale`
  void _calculateScaleBoundary(Rect cropWindow) {
    VecMath64.Matrix4 transform = VecMath64.Matrix4.rotationZ(_rotation);
    Rect contentBox = Rect.fromLTWH(0, 0, _originSize.width, _originSize.height);
    contentBox = MatrixUtils.transformRect(transform, contentBox);
    _minScale = max(cropWindow.width / contentBox.width, cropWindow.height / contentBox.height);
    _maxScale = maxScale * _minScale;
    if ( _rotationRefScale != null) {
      _scale = _validateScale(_rotationRefScale!);
    } else {
      _scale = _validateScale(_scale ?? _minScale);
    }
  }

  // Rotate by Long press
  void _changeRoration(double diff) {
    _rotation = _validateRotation(_rotation + diff);
    _calculateSizes();
    _moveToRefPoint(_gestureLocalPoint, _gestureContentPoint);
  }

  // Zoom by Scroll (desktop) or rotate & zoom by 2 fingers (phone)
  void _changeScaleRotation(double scaleDiff, double rotationDiff) {
    if (_scale != null && _scaleRef != null) {
      double scale = _validateScale(_scaleRef! + scaleDiff);
      _scale = scale;
    }
    if (_rotationRef != null) {
      _rotation = _validateRotation(_rotationRef! + rotationDiff);
    }
    _calculateSizes();
    _moveToRefPoint(_gestureLocalPoint, _gestureContentPoint);
  }

  // Validate current translation of InteractiveViewer
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

  // Core function
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

  // Util function
  Offset _getTranslation() {
    VecMath64.Vector3 translation = _transformer.value.getTranslation();
    return Offset(max(0, -translation.x), max(0, -translation.y));
  }

  // Widget function
  void _gestureStarts(Offset point) {
    _gestureLocalPoint = point;
    _gestureContentPoint = _calculateContentPoint(point);
    _scaleRef = _scale;
    _rotationRef = _rotation;
  }

  // Widget function
  void _gestureNotifies(ScaleUpdateDetails details) {
    double scaleDiff = details.scale - 1;
    _changeScaleRotation(scaleDiff, details.rotation);
  }

  // Widget function
  void _gestureEnds() {
    _gestureLocalPoint = null;
    _gestureContentPoint = null;
    _scaleRef = null;
    _rotationRef = null;
  }

  // Widget function
  void _longPressStart(LongPressStartDetails details) {
    _longPressLast = details.localPosition;
    _rotationRefScale = _scale;
    _gestureStarts(_localCenter);
  }

  // Widget function
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

  // Widget function
  void _longPressEnd(LongPressEndDetails details) {
    _longPressLast = null;
    _rotationRefScale = null;
    _gestureEnds();
  }

  // Widget function
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

  bool _validateGesture(int count) => isPhone() ? count == 2 : count == 0;

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