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

/*
Layout of crop view

+-ScrollView (InteractiveViewer)----------------------+
|+-Container view (SizedBox)-------------------------+|
||                                                   ||
||  +-Content View (Stack > Positioned)-----------+  ||
||  | <target view>                               |  ||
||  +---------------------------------------------+  ||
||                                                   ||
|+---------------------------------------------------+|
+-----------------------------------------------------+

- Size of Content View is Original Size * current scale level.
- Size of Container View and position of Content View depend on the crop window (so user can not scroll/drag the Content View outsize the crop window).
(that why we zoom by manualy setting the size of Content View instead of using scaling feature of InteractiveViewer).
*/

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
  /// Original size of target view.
  Size _originSize = Size.zero;
  /// Current size of this view.
  Size _bounds = Size.zero;
  // Data need to be calculated
  /// Size of Content View.
  Size _contentSize = Size.zero;
  /// Size of Container View.
  Size _containerSize = Size.zero;
  /// Positon of Content View.
  Offset _contentPosition = Offset.zero;
  // Tracking data
  /// Current zoom level.
  double? _scale;
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

  // Calculate location on Target View coordinates (Content View without scale) from point on widget coordinate
  Offset _calculateContentPoint(Offset localPoint) {
    Offset contentOffset = _getTranslation();
    Offset containerPositon = Offset(contentOffset.dx + localPoint.dx, contentOffset.dy + localPoint.dy);
    return Offset(
      (containerPositon.dx - _contentPosition.dx) / _scale!,
      (containerPositon.dy - _contentPosition.dy) / _scale!
    );
  }

  // Calculate location on Container View coordinates from point on Target View coordinates (Content View without scale or rotate)
  Offset _calculateContainerPoint(Offset contentPoint) {
    Offset contentPosition = Offset(contentPoint.dx * _scale!, contentPoint.dy * _scale!);
    return Offset(contentPosition.dx + _contentPosition.dx, contentPosition.dy + _contentPosition.dy);
  }

  // Set Content View positon to move the point on Container View to the point on widget as close as posible
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

  // After some actions (eg. rotate or zoom), content view position may change.
  // So we should move the reference point on target view back to the reference poin on widget.
  void _moveToRefPoint(Offset? localRefPoint, Offset? contentRefPoint) {
    if (localRefPoint != null && contentRefPoint != null) {
      Offset point = _calculateContainerPoint(contentRefPoint);
      _moveContainerPointToLocalPoint(point, localRefPoint);
    }
  }

  void _startScale(Offset point) {
    _scaleRef = _scale;
    _gestureLocalPoint = point;
    _gestureContentPoint = _calculateContentPoint(point);
  }

  void _endScale() {
    _scaleRef = null;
    _gestureLocalPoint = null;
    _gestureContentPoint = null;
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
    _moveToRefPoint(_gestureLocalPoint, _gestureContentPoint);
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

  @override
  void initState() {
    super.initState();
    widget.adapter._originSize = Size(widget.originWidth, widget.originHeight);
    widget.adapter._setState = setState;
  }

  bool _isZooming(int count) {
    if (Platform.isAndroid || Platform.isIOS) {
      return count == 2;
    }
    return count == 0;
  }

  void _gestureOnStart(ScaleStartDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    widget.adapter._startScale(details.localFocalPoint);
  }

  void _gestureOnNotified(ScaleUpdateDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    double scaleDiff = details.scale - 1;
    widget.adapter._changeScale(scaleDiff);
  }

  void _gestureOnEnd(ScaleEndDetails details) {
    if (!_isZooming(details.pointerCount)) return;
    widget.adapter._endScale();
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
                  top: widget.adapter._contentPosition.dy,
                  left: widget.adapter._contentPosition.dx,
                  width: widget.adapter._contentSize.width,
                  height: widget.adapter._contentSize.height,
                  child: widget.child
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