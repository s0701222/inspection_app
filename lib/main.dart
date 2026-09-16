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

  // Get GPS Location & Format exactly like "22.325727°N, 114.204815°E"
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
      String latDir = position.latitude >= 0 ? 'N' : 'S';
      String lngDir = position.longitude >= 0 ? 'E' : 'W';
      _locationData = '${position.latitude.abs().toStringAsFixed(6)}°$latDir, ${position.longitude.abs().toStringAsFixed(6)}°$lngDir';
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

  // Generate PDF (Updated to match Reference PDF Layout)
  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    
    // Formatting Dates and Times
    final String dateStr = DateFormat('dd MMM yyyy').format(_startDate);
    final String startTimeStr = _startTime != null ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}' : '--:--';
    final String endTimeStr = _endTime != null ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}' : '--:--';
    final String timeRange = '$startTimeStr-$endTimeStr';
    final String submitTime = '${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())} HKT';

    // Reusable TextField builder for PDF
    pw.Widget buildPdfTextField(String label, String value) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value.isEmpty ? 'Nil' : value, style: const pw.TextStyle(fontSize: 11)),
          ]
        )
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Submitted: $submitTime GPS: $_locationData', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.Text('OP10-1', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ]
            )
          );
        },
        build: (pw.Context context) {
          return [
            // Header
            pw.Center(
              child: pw.Text('Inspection Record Form', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 20),

            // Basic Info Block
            pw.Text('Project/Contract No.: ${_projectController.text}', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Text('Inspection Date: $dateStr', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Text('Time: $timeRange', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Text('Inspection Type: $_inspectionType', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 20),

            // General Conditions Table
            pw.Text('General Conditions', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3.5),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Satisfactory', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Remarks', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  ]
                ),
                ..._conditions.map((cond) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(cond.title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          if (cond.subtitle.isNotEmpty) 
                            pw.Container(
                              margin: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text(cond.subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800))
                            ),
                        ]
                      )
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Center(child: pw.Text(cond.isYes ? 'Yes' : 'No', style: const pw.TextStyle(fontSize: 10)))
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(cond.remarksController.text.isEmpty ? '' : cond.remarksController.text, style: const pw.TextStyle(fontSize: 10))
                    ),
                  ]
                )).toList(),
              ]
            ),
            pw.SizedBox(height: 20),

            // Text Fields
            buildPdfTextField('Item Inspected:', _itemInspectedController.text),
            buildPdfTextField('Inspection Findings/Results:', _findingsController.text),
            buildPdfTextField('Action Taken:', _actionTakenController.text),
            
            pw.SizedBox(height: 10),
            pw.Text('Inspected by: ________________________', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 15),

            buildPdfTextField('Other Witnessing Parties (if any):', _witnessingPartiesController.text),
            
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Signed by: ________________________', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Signature Date: ________________________', style: const pw.TextStyle(fontSize: 11)),
              ]
            ),
            
            pw.SizedBox(height: 30),

            // Photos Section (Table Format)
            if (_images.isNotEmpty) ...[
              pw.Text('Photos Attached', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                },
                children: _images.asMap().entries.map((entry) {
                  int idx = entry.key;
                  XFile image = entry.value;
                  final imageBytes = File(image.path).readAsBytesSync();
                  final pdfImage = pw.MemoryImage(imageBytes);

                  return pw.TableRow(
                    children: [
                      // Image Cell
                      pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        height: 200,
                        alignment: pw.Alignment.center,
                        child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                      ),
                      // Text Metadata Cell
                      pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        alignment: pw.Alignment.topLeft,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          mainAxisAlignment: pw.MainAxisAlignment.start,
                          children: [
                            pw.Text('Photo ${idx + 1}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                            pw.SizedBox(height: 8),
                            pw.Text('Time: $submitTime', style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(height: 4),
                            pw.Text('GPS: $_locationData', style: const pw.TextStyle(fontSize: 10)),
                          ]
                        )
                      ),
                    ]
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

            // Photos Section 
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
