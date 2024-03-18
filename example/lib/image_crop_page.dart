import 'package:flutter/material.dart';
import 'package:image/image.dart';
import 'package:crop_view/crop_view.dart';
import 'package:crop_view/crop_mask_view.dart';
import 'package:myimagecrop/anti_confuse.dart';

class ImageCropPage extends StatefulWidget {

  final ImgImage image;
  final void Function(Rect) onCompletion;

  const ImageCropPage({super.key, required this.image, required this.onCompletion});

  @override
  State<StatefulWidget> createState() => _ImageCropPageState();

}

class _ImageCropPageState extends State<ImageCropPage> {

  final CropMaskPainter _maskPainter = const CropMaskPainter(shape: CropMaskShape.oval, shapeRatio: 1, cropWindowBorder: 5);
  late CropViewAdapter _adapter;

  @override
  void initState() {
    super.initState();
    _adapter = CropViewAdapter(calculateCropWindow: (bounds) => _maskPainter.calculateCropWindow(bounds));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.lightBlue,
        title: const Text("Image crop", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: _onSubmit,
            icon: const Icon(Icons.save),
          )
        ],
      ),
      body: CropView(
        adapter: _adapter,
        originWidth: widget.image.width.toDouble(),
        originHeight: widget.image.height.toDouble(),
        mask: CropMaskView(painter: _maskPainter),
        child: Container(
          color: Colors.red,
          child: FittedBox(fit: BoxFit.fill, child: UiImage.memory(encodeJpg(widget.image))),
        )
      )
    );
  }

  void _onSubmit() {
    Rect cropFrame = _adapter.getCropFrame();
    Navigator.of(context).pop();
    widget.onCompletion(cropFrame);
  }

}
