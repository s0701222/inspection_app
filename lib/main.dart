import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const InspectionApp());
}

class InspectionApp extends StatelessWidget {
  const InspectionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inspection Record E-form',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const InspectionForm(),
    );
  }
}

class InspectionForm extends StatefulWidget {
  const InspectionForm({Key? key}) : super(key: key);

  @override
  State<InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends State<InspectionForm> {
  // 表單預設文字
  final TextEditingController _remarkController = TextEditingController(text: 'Nil');
  final TextEditingController _attachmentController = TextEditingController(text: 'Please refer to the photos attached');
  
  String _locationData = 'Fetching location...';
  List<XFile> _images = [];

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  // 取得 GPS 定位
  Future<void> _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationData = 'Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationData = 'Location permissions are denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationData = 'Location permissions are permanently denied.');
      return;
    } 

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _locationData = 'Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}';
    });
  }

  // 拍照或選擇照片
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? selectedImages = await picker.pickMultiImage();
    if (selectedImages != null && selectedImages.isNotEmpty) {
      setState(() {
        _images.addAll(selectedImages);
      });
    }
  }

  // 產生並預覽/儲存 PDF
  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final String currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // 標題區塊
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, // 修正處
                children: [
                  pw.Text('Inspection Record', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            // 表單內容區塊
            pw.Text('Location (GPS):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(_locationData),
            pw.SizedBox(height: 10),
            
            pw.Text('Remarks:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(_remarkController.text),
            pw.SizedBox(height: 10),

            pw.Text('Attachments:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(_attachmentController.text),
            pw.SizedBox(height: 20),

            // 照片與 Metadata 區塊
            if (_images.isNotEmpty) ...[
              pw.Text('Photo Evidences:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Wrap(
                spacing: 20,
                runSpacing: 20,
                crossAxisAlignment: pw.WrapCrossAlignment.start, // 修正處
                children: _images.map((image) {
                  final imageBytes = File(image.path).readAsBytesSync();
                  final pdfImage = pw.MemoryImage(imageBytes);
                  return pw.Container(
                    width: 200,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start, // 修正處
                      children: [
                        pw.Image(pdfImage, fit: pw.BoxFit.contain),
                        pw.SizedBox(height: 5),
                        pw.Text('Timestamp: $currentTime', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('GPS: $_locationData', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ]
          ];
        },
      ),
    );

    // 呼叫 Printing 套件來產生預覽與儲存功能 (支援 Windows / Android)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Inspection_Record_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection App')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // GPS 顯示
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on, color: Colors.red),
              title: const Text('Current Location'),
              subtitle: Text(_locationData),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _getLocation,
              ),
            ),
            const Divider(),
            
            // 表單輸入
            TextField(
              controller: _remarkController,
              decoration: const InputDecoration(labelText: 'Remarks'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _attachmentController,
              decoration: const InputDecoration(labelText: 'Attachments info'),
            ),
            const SizedBox(height: 24),
            
            // 照片區塊
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Photos:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add Photos'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_images.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _images.map((img) => Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Image.file(File(img.path), width: 100, height: 100, fit: BoxFit.cover),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _images.remove(img);
                        });
                      },
                    )
                  ],
                )).toList(),
              ),
          ],
        ),
      ),
      // 產生 PDF 按鈕
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generatePdf,
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Generate PDF'),
      ),
    );
  }
}
