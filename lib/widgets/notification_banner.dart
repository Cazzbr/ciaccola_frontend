import 'dart:async';
import 'package:flutter/material.dart';

/// A transient top-of-screen banner that slides in, lingers, then slides out.
///
/// Usage:
///   NotificationBanner.show(
///     context,
///     icon: Icons.message,
///     title: 'Alice',
///     body: 'Hey there!',
///     onTap: () { /* navigate */ },
///   );
class NotificationBanner extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;
  final Duration duration;

  const NotificationBanner({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.onTap,
    this.duration = const Duration(seconds: 4),
  });

  // ---------------------------------------------------------------------------
  // Factory helper
  // ---------------------------------------------------------------------------

  static OverlayEntry show(
    BuildContext context, {
    required IconData icon,
    Color iconColor = const Color(0xFF3B82F6),
    required String title,
    required String body,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationBanner(
        icon: icon,
        iconColor: iconColor,
        title: title,
        body: body,
        onTap: onTap,
        duration: duration,
        onDismiss: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }

  @override
  State<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _ctrl.forward();

    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.stop();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    _timer?.cancel();
    await _ctrl.reverse();
    // The widget may have been disposed while the reverse animation was running
    // (e.g. hot restart, navigation). Calling onDismiss() after disposal
    // triggers entry.remove() → markNeedsBuild on the Overlay → schedules a
    // frame → "Trying to render a disposed EngineFlutterView" on web.
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: _BannerCard(
            icon: widget.icon,
            iconColor: widget.iconColor,
            title: widget.title,
            body: widget.body,
            onTap: widget.onTap != null
                ? () {
                    _dismiss();
                    widget.onTap!();
                  }
                : null,
            onDismiss: _dismiss,
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _BannerCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: const Color(0xFF1E293B),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
