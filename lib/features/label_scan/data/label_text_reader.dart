import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:opennutritracker/features/label_scan/domain/label_row_builder.dart';

/// Reads the rows of text in a photo of a nutrition label.
abstract class LabelTextReader {
  Future<List<String>> readRows(String imagePath);

  Future<void> close();
}

/// On-device text recognition with ML Kit. Nothing leaves the phone.
class MlKitLabelTextReader implements LabelTextReader {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  Future<List<String>> readRows(String imagePath) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final lines = <OcrLine>[
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            line.boundingBox.left,
            line.boundingBox.top,
            line.boundingBox.right,
            line.boundingBox.bottom,
          ),
    ];
    return LabelRowBuilder.rows(lines);
  }

  @override
  Future<void> close() => _recognizer.close();
}
