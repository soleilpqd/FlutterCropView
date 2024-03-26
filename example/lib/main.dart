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
import 'package:image_picker/image_picker.dart';
import 'package:myimagecrop/anti_confuse.dart';
import 'package:myimagecrop/image_crop_page.dart';
import 'package:myimagecrop/isolations.dart';

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
  UiImage? _uiImage;
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
      body: _uiImage != null ?
        Center(child: _uiImage) :
        const Center(child: Text(
          "Use 'Pick' to open an image.\nThen use 'Crop' to crop image.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ))
    );
  }

  void _onPickImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (error) {
      print("FAIL $error");
      return;
    }
    if (file != null) {
      // ignore: use_build_context_synchronously
      showLoading(context);
      Isolations.loadImageFromFile(file).then((result) {
        setState(() {
          _image = result.$1;
          _uiImage = result.$2;
        });
        closeLoading();
      });
    }
  }

  void _onCropImage() {
    if (_image != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageCropPage(image: _image!, onCompletion: _onCropImageSubmit)));
    }
  }

  void _onCropImageSubmit(double rotation, Rect cropFrame) {
    showLoading(context);
    Isolations.cropImage(_image!, rotation, cropFrame).then((result) {
      setState(() {
        _image = result.$1;
        _uiImage = result.$2;
      });
      closeLoading();
    });
  }

}
