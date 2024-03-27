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

import 'package:flutter/material.dart';

class CropMaskView extends StatelessWidget {

  final CustomPainter painter;
  const CropMaskView({super.key, required this.painter});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => CustomPaint(
      painter: painter,
      size: Size(constraints.maxWidth, constraints.maxHeight),
    ));
  }

}

enum CropMaskShape { rectangle, oval }
enum CropMaskPadding { relative, fixed }

class CropMaskPainter extends CustomPainter {

  // For development
  final double _gridWeight = 0;
  final double _gridSize = 10;

  /// Background color. Default: grey with alpha 128.
  final Color? backgroundColor;
  /// Shape of crop window. Default rectangle.
  final CropMaskShape shape;
  /// Ratio of width/height of shape. Default 1 (it means default crop window square).
  final double shapeRatio;
  /// Padding mode: how to determine the minimum space between crop window and widget border.<br/>
  /// Default: `relative`.<br/>
  /// See `paddingParam` for explain.<br/>
  final CropMaskPadding padding;
  /// Padding param.
  ///  - `padding` mode is `relative`: minimum padding = widget size * `paddingParam`. Default value: 0.1 (1%).
  ///  - `padding` mode is `fixed`: minimum padding = `paddingParam`.
  final double paddingParam;
  /// Width of crop window border. Default 1.
  final double cropWindowBorder;
  /// Color of crop window border. Default white.
  final Color? cropWindowBorderColor;

  const CropMaskPainter({
    this.backgroundColor,
    this.shape = CropMaskShape.rectangle,
    this.shapeRatio = 1,
    this.padding = CropMaskPadding.relative,
    this.paddingParam = 0.1,
    this.cropWindowBorder = 1,
    this.cropWindowBorderColor
  });

  Rect calculateCropWindow(Size bounds) {
    double paddingSpace = paddingParam;
    if (padding == CropMaskPadding.relative) {
      if (shapeRatio > 1) { // Landscaple crop window
        paddingSpace = paddingParam * bounds.width;
      } else { // Portrait crop window
        paddingSpace = paddingParam * bounds.height;
      }
    }
    double cropWinWidth = 0;
    double cropWinHeight = 0;
    if (shapeRatio > 1) { // Landscaple
      cropWinWidth = bounds.width - paddingSpace;
      cropWinHeight = cropWinWidth / shapeRatio;
      if (cropWinHeight > bounds.height) {
        if (padding == CropMaskPadding.relative) {
          paddingSpace = paddingParam * bounds.height;
        }
        cropWinHeight = bounds.height - paddingSpace;
        cropWinWidth = cropWinHeight * shapeRatio;
      }
    } else { // Portrait
      cropWinHeight = bounds.height - paddingSpace;
      cropWinWidth = cropWinHeight * shapeRatio;
      if (cropWinWidth > bounds.width) {
        if (padding == CropMaskPadding.relative) {
          paddingSpace = paddingParam * bounds.width;
        }
        cropWinWidth = bounds.width - paddingSpace;
        cropWinHeight = cropWinWidth / shapeRatio;
      }
    }

    return Rect.fromLTWH(
      (bounds.width - cropWinWidth) / 2,
      (bounds.height - cropWinHeight) / 2,
      cropWinWidth, cropWinHeight);
  }

  @override
  void paint(Canvas canvas, Size size) {
    Rect cropWindow = calculateCropWindow(size);
    Paint paint = Paint();
    paint.color = backgroundColor ?? Colors.grey.withAlpha(128);
    paint.style = PaintingStyle.fill;
    Path path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    switch (shape) {
      case CropMaskShape.rectangle:
        path.addRect(cropWindow);
      case CropMaskShape.oval:
        path.addOval(cropWindow);
    }
    path.close();
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
    if (cropWindowBorder > 0) {
      paint.color = cropWindowBorderColor ?? Colors.white;
      paint.strokeWidth = cropWindowBorder;
      paint.style = PaintingStyle.stroke;
      Rect borderRect = Rect.fromLTWH(
        cropWindow.left - cropWindowBorder / 2,
        cropWindow.top - cropWindowBorder / 2,
        cropWindow.width + cropWindowBorder,
        cropWindow.height + cropWindowBorder
      );
      Path borderPath = Path();
      switch (shape) {
        case CropMaskShape.rectangle:
          borderPath.addRect(borderRect);
        case CropMaskShape.oval:
          borderPath.addOval(borderRect);
      }
      canvas.drawPath(borderPath, paint);
    }
    if (_gridSize > 0 && _gridWeight > 0) {
      _paintGrid(canvas, size, cropWindow);
    }
  }

  void _paintGrid(Canvas canvas, Size size, Rect cropWindow) {
    Paint paint = Paint();
    paint.color = (backgroundColor ?? Colors.grey).withAlpha(128);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = _gridWeight;
    double temp = size.width / 2;
    for (double x = temp - (_gridSize * (temp ~/ _gridSize)); x < size.width; x += _gridSize) {
      Path path = Path();
      path.moveTo(x, 0);
      path.lineTo(x, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
    temp = size.height / 2;
    for (double y = temp - (_gridSize * (temp ~/ _gridSize)); y < size.height; y += _gridSize) {
      Path path = Path();
      path.moveTo(0, y);
      path.lineTo(size.width, y);
      path.close();
      canvas.drawPath(path, paint);
    }
    paint.color = Colors.red.withAlpha(128);
    paint.strokeWidth *= 2;
    Path path = Path();
    path.moveTo(size.width / 2 - _gridSize, size.height / 2);
    path.lineTo(size.width / 2 + _gridSize, size.height / 2);
    path.moveTo(size.width / 2, size.height / 2 - _gridSize);
    path.lineTo(size.width / 2, size.height / 2 + _gridSize);
    path.moveTo(cropWindow.left, cropWindow.top + _gridSize);
    path.lineTo(cropWindow.left, cropWindow.top);
    path.lineTo(cropWindow.left + _gridSize, cropWindow.top);
    path.moveTo(cropWindow.left + cropWindow.width - _gridSize, cropWindow.top);
    path.lineTo(cropWindow.left + cropWindow.width, cropWindow.top);
    path.lineTo(cropWindow.left + cropWindow.width, cropWindow.top + _gridSize);
    path.moveTo(cropWindow.left + cropWindow.width, cropWindow.top + cropWindow.height - _gridSize);
    path.lineTo(cropWindow.left + cropWindow.width, cropWindow.top + cropWindow.height);
    path.lineTo(cropWindow.left + cropWindow.width - _gridSize, cropWindow.top + cropWindow.height);
    path.moveTo(cropWindow.left + _gridSize, cropWindow.top + cropWindow.height);
    path.lineTo(cropWindow.left, cropWindow.top + cropWindow.height);
    path.lineTo(cropWindow.left, cropWindow.top + cropWindow.height - _gridSize);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

}