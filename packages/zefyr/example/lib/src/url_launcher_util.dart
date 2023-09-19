import 'package:url_launcher/url_launcher.dart';

Future<void> openUrl(String? url) async {
  if (url == null) return;
  final uri = Uri.parse(url);
  final result = await canLaunchUrl(uri);
  if (result) {
    await launchUrl(uri);
  }
}
