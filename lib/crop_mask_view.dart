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
    Path path1 = Path();
    path1.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    Path path2 = Path();
    switch (shape) {
      case CropMaskShape.rectangle:
        path2.addRect(cropWindow);
      case CropMaskShape.oval:
        path2.addOval(cropWindow);
    }
    Path path = Path.combine(
      PathOperation.difference,
      path1,
      path2
    );
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

}