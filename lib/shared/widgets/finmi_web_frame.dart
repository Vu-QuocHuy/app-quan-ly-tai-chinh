import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';

/// Wraps the Flutter application in a realistic mobile phone frame when running on desktop web browsers.
/// This allows developers and users to view the app in authentic mobile dimensions without resizing the browser window,
/// and enables opening two browser tabs side-by-side (e.g. localhost:8080 and localhost:8081) for multi-account testing.
class FinmiWebFrame extends StatefulWidget {
  const FinmiWebFrame({required this.child, super.key});

  final Widget child;

  @override
  State<FinmiWebFrame> createState() => _FinmiWebFrameState();
}

class _FinmiWebFrameState extends State<FinmiWebFrame> {
  // Enabled by default on desktop web screens
  bool _phoneFrameEnabled = true;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        // If the viewport itself is already mobile-sized (< 560px), render directly
        if (constraints.maxWidth < 560) {
          return widget.child;
        }

        final tr = context.tr;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (!_phoneFrameEnabled) {
          return Stack(
            children: [
              widget.child,
              Positioned(
                top: 12,
                right: 16,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(24),
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => setState(() => _phoneFrameEnabled = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.smartphone_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            tr.phoneFrameMode,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Phone Frame dimensions
        const phoneWidth = 412.0;
        final availableHeight = constraints.maxHeight;
        final phoneHeight = math.min(
          880.0,
          math.max(600.0, availableHeight - 64.0),
        );

        // Modern canvas background
        final canvasBg = isDark
            ? const Color(0xFF090D16)
            : const Color(0xFFE2E8F0);

        final frameBorderColor = isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFF334155);

        return Material(
          color: canvasBg,
          child: Column(
            children: [
              // Top control bar on desktop web canvas
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fiber_manual_record,
                            size: 10,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Finmi Mobile Runner',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr.dualInstanceTip,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Switch to Full Screen
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () =>
                          setState(() => _phoneFrameEnabled = false),
                      icon: const Icon(Icons.fullscreen, size: 18),
                      label: Text(
                        tr.fullScreenMode,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              // Centered Phone Device
              Expanded(
                child: Center(
                  child: Container(
                    width: phoneWidth,
                    height: phoneHeight,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(44),
                      border: Border.all(color: frameBorderColor, width: 9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.6 : 0.25,
                          ),
                          blurRadius: 32,
                          spreadRadius: 2,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(35),
                      child: Stack(
                        children: [
                          // App rendered with mobile MediaQuery
                          Positioned.fill(
                            child: MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                size: Size(phoneWidth, phoneHeight),
                                padding: const EdgeInsets.only(
                                  top: 32,
                                  bottom: 12,
                                ),
                                viewPadding: const EdgeInsets.only(
                                  top: 32,
                                  bottom: 12,
                                ),
                              ),
                              child: widget.child,
                            ),
                          ),

                          // Dynamic island / Camera pill
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 92,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1E293B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
