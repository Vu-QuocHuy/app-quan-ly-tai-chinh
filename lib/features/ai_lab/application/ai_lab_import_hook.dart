import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// An image the AI Lab wants the app to import as if the user had picked it
/// (control panel sample receipts, batch runner, web bridge).
///
/// `AppShell` listens to this provider in debug builds, sets it back to `null`
/// and feeds the file to its normal image import path.
final aiLabImportRequestProvider = StateProvider<XFile?>((ref) => null);
