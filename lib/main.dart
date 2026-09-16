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
      title: 'Inspection Record Form',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const InspectionForm(),
    );
  }
}

class ConditionItemModel {
  final String title;
  final String subtitle;
  bool isYes;
  final TextEditingController remarksController;

  ConditionItemModel({
    required this.title,
    required this.subtitle,
    this.isYes = true,
    TextEditingController? remarksController,
  }) : remarksController = remarksController ?? TextEditingController();
}

class InspectionForm extends StatefulWidget {
  const InspectionForm({Key? key}) : super(key: key);

  @override
  State<InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends State<InspectionForm> {
  // Form Controllers
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _itemInspectedController = TextEditingController();
  final TextEditingController _findingsController = TextEditingController(text: 'Please refer to the photos attached');
  final TextEditingController _actionTakenController = TextEditingController(text: 'Nil');
  final TextEditingController _witnessingPartiesController = TextEditingController(text: 'Nil');

  // Date & Time
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Inspection Type
  String _inspectionType = 'General';
  final List<String> _inspectionTypes = ['General', 'Safety', 'Environmental', 'Quality'];

  // Conditions List
  final List<ConditionItemModel> _conditions = [
    ConditionItemModel(
      title: 'A. Site Safety',
      subtitle: '(including accident/fire prevention, environment/hygiene/first-aid at workplace, manual handling and F&IU regulations if applicable)',
    ),
    ConditionItemModel(
      title: 'B. Site Security/Cleanliness',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'C. Progress against the agreed programme',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'D. Environmental issue/Waste Management',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'E. Appropriate workers with adequate protection',
      subtitle: '(including Personal Protective Equipment)',
    ),
  ];

  String _locationData = 'Fetching location...';
  List<XFile> _images = [];

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  // Get GPS Location
  Future<void> _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationData = 'Location services disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationData = 'Location permissions denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationData = 'Location permissions permanently denied.');
      return;
    } 

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _locationData = 'Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}';
    });
  }

  // Pick Images
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? selectedImages = await picker.pickMultiImage();
    if (selectedImages != null && selectedImages.isNotEmpty) {
      setState(() {
        _images.addAll(selectedImages);
      });
    }
  }

  // Date Picker
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  // Time Picker
  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? (_startTime ?? TimeOfDay.now()) : (_endTime ?? TimeOfDay.now()),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // Generate PDF
  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final String currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final String startDateStr = DateFormat('dd/MM/yyyy').format(_startDate);
    final String endDateStr = DateFormat('dd/MM/yyyy').format(_endDate);
    final String startTimeStr = _startTime != null ? _startTime!.format(context) : '--:--';
    final String endTimeStr = _endTime != null ? _endTime!.format(context) : '--:--';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Inspection Record Form', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // Basic Info Summary
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Project/Contract No.: ${_projectController.text}'),
                      pw.Text('Start: $startDateStr $startTimeStr'),
                      pw.Text('End: $endDateStr $endTimeStr'),
                      pw.Text('Type: $_inspectionType'),
                      pw.Text('GPS: $_locationData', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ]
                  )
                )
              ]
            ),
            pw.SizedBox(height: 20),

            // General Conditions
            pw.Text('General Conditions', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            ..._conditions.map((cond) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(cond.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        if (cond.subtitle.isNotEmpty)
                          pw.Text(cond.subtitle, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      ]
                    )
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(cond.isYes ? '[ Yes ]' : '[ No ]', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: cond.isYes ? PdfColors.blue800 : PdfColors.red800))
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Remarks: ${cond.remarksController.text.isEmpty ? "None" : cond.remarksController.text}', style: const pw.TextStyle(fontSize: 10))
                  ),
                ]
              )
            )),

            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 10),

            // Text Fields
            pw.Text('Item Inspected:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(_itemInspectedController.text.isEmpty ? 'Nil' : _itemInspectedController.text, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),

            pw.Text('Inspection Findings/Results:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(_findingsController.text, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),

            pw.Text('Action Taken:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(_actionTakenController.text, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),

            pw.Text('Other Witnessing Parties (if any):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(_witnessingPartiesController.text, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 20),

            // Photos
            if (_images.isNotEmpty) ...[
              pw.Text('Photos', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _images.map((image) {
                  final imageBytes = File(image.path).readAsBytesSync();
                  final pdfImage = pw.MemoryImage(imageBytes);
                  return pw.Container(
                    width: 150,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Image(pdfImage, fit: pw.BoxFit.contain),
                        pw.SizedBox(height: 4),
                        pw.Text('Time: $currentTime', style: const pw.TextStyle(fontSize: 7)),
                        pw.Text('GPS: $_locationData', style: const pw.TextStyle(fontSize: 7)),
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Inspection_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.description, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Inspection Record Form', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: _generatePdf,
              icon: const Icon(Icons.download, color: Colors.white, size: 18),
              label: const Text('Generate PDF', style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project No
            const Text('Project/Contract No. *', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _projectController,
              decoration: const InputDecoration(hintText: 'e.g. HK/2026/0042', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            // Dates
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectDate(context, true),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                              const Icon(Icons.calendar_today, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('End Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectDate(context, false),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('dd/MM/yyyy').format(_endDate)),
                              const Icon(Icons.calendar_today, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Times
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start Time'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(context, true),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_startTime != null ? _startTime!.format(context) : '--:--'),
                              const Icon(Icons.access_time, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('End Time'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(context, false),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_endTime != null ? _endTime!.format(context) : '--:--'),
                              const Icon(Icons.access_time, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Inspection Type
            const Text('Inspection Type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _inspectionType,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: _inspectionTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
              onChanged: (val) => setState(() => _inspectionType = val!),
            ),
            const SizedBox(height: 32),

            // General Conditions Block
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('General Conditions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  // Map through conditions for aligned layout
                  ..._conditions.map((cond) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Title and Subtitle
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cond.title, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                              if (cond.subtitle.isNotEmpty)
                                Text(cond.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        // Right side: Radio buttons and Remarks
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Radio<bool>(
                                value: true,
                                groupValue: cond.isYes,
                                activeColor: Colors.indigo,
                                onChanged: (val) => setState(() => cond.isYes = val!),
                              ),
                              const Text('Yes'),
                              const SizedBox(width: 8),
                              Radio<bool>(
                                value: false,
                                groupValue: cond.isYes,
                                activeColor: Colors.indigo,
                                onChanged: (val) => setState(() => cond.isYes = val!),
                              ),
                              const Text('No'),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: cond.remarksController,
                                    decoration: InputDecoration(
                                      hintText: 'Remarks',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: Colors.grey.shade300)
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Multiline Text Fields
            const Text('Item Inspected', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _itemInspectedController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              maxLines: 4,
            ),
            const SizedBox(height: 20),

            const Text('Inspection Findings/Results', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _findingsController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              maxLines: 4,
            ),
            const SizedBox(height: 20),

            const Text('Action Taken', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _actionTakenController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            const Text('Other Witnessing Parties (if any)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _witnessingPartiesController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),

            // Photos Section (已修正邊框樣式)
            const Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickImages,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.camera_alt_outlined, size: 36, color: Colors.blueGrey),
                    SizedBox(height: 12),
                    Text('Tap to take or upload photos', style: TextStyle(color: Colors.blueGrey, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('GPS and time captured — photos stay on your device until the PDF is made', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Image Preview Block
            if (_images.isNotEmpty)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _images.map((img) => Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(img.path), width: 120, height: 120, fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close, color: Colors.red, size: 18),
                          onPressed: () => setState(() => _images.remove(img)),
                        ),
                      ),
                    )
                  ],
                )).toList(),
              ),
            const SizedBox(height: 24),

            // Privacy Notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: const [
                  Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('Nothing is uploaded — photos, location and the report stay on this device.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
