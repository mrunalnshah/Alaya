import 'package:share_plus/share_plus.dart';

/// Hands text to the system share sheet.
///
/// **A port with one method, and the containment is the point.** `B4_DATA`'s `ShareBackupTransfer`
/// records why: `share_plus` v11 replaced `Share.shareXFiles` with
/// `SharePlus.instance.share(ShareParams(...))`, and it calls itself *"the sharper edge"* of its two
/// dependencies. Keeping every reference in one small file means the next such change has exactly one
/// casualty rather than a screen.
///
/// It also keeps `share_plus` out of the widget tree, so the sheet above is testable without a plugin
/// channel — a widget test can override this with a fake that records what it was handed.
abstract interface class SplitSharePort {
  /// Offers [text] to the system share sheet.
  Future<void> shareText(String text);
}

/// The production port.
final class SystemSplitShare implements SplitSharePort {
  /// Creates the port.
  const SystemSplitShare();

  @override
  Future<void> shareText(String text) =>
      SharePlus.instance.share(ShareParams(text: text));
}
