import 'package:flutter/widgets.dart';

/// Window width from which the library and the player sit side by side
/// (desktop / tablet). Below it the player is a separate full screen.
const double kWideLayoutMinWidth = 900;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutMinWidth;

/// Width of the "now playing" panel in the wide layout.
double nowPlayingPanelWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.36).clamp(340.0, 440.0);
