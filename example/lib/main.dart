import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myimagecrop/anti_confuse.dart';
import 'package:myimagecrop/image_crop_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Image'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  ImgImage? _image;
  BuildContext? _loadingContext;

  void showLoading(BuildContext context) {
    _loadingContext = context;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: Wrap(children: [CircularProgressIndicator()]))
    );
  }

  void closeLoading() {
    if (_loadingContext != null) {
      Navigator.of(_loadingContext!).pop();
      _loadingContext = null;
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.lightBlue,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: _onCropImage, child: const Text("Crop")),
          TextButton(onPressed: _onPickImage, child: const Text("Pick")),
        ],
      ),
      body: _image != null ?
        Center(child: UiImage.memory(encodeJpg(_image!))) :
        const Center(child: Text(
          "Use 'Pick' to open an image.\nThen use 'Crop' to crop image.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ))
    );
  }

  void _onPickImage() async {
    final ImagePicker picker = ImagePicker();
    showLoading(context);
    try {
      XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null && context.mounted) {
        // ignore: use_build_context_synchronously
        Uint8List data = await file.readAsBytes();
        setState(() {
          _image = decodeImage(data);
        });
      }
    } catch (error) {
      print("FAIL $error");
    }
    closeLoading();
  }

  void _onCropImage() {
    if (_image != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageCropPage(image: _image!, onCompletion: _onCropImageSubmit)));
    }
  }

  void _onCropImageSubmit(Rect cropFrame) {
    setState(() {
      _image = copyCrop(
        _image!,
        x: cropFrame.left.toInt(),
        y: cropFrame.top.toInt(),
        width: cropFrame.width.toInt(),
        height: cropFrame.height.toInt()
      );
    });
  }

}
