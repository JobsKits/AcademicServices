import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget browserShopLink({
  required Uri route,
  required String label,
  required Widget child,
  required VoidCallback onNavigate,
  required Color focusColor,
}) => _BrowserShopLink(
  route: route,
  label: label,
  onNavigate: onNavigate,
  focusColor: focusColor,
  child: child,
);

class _BrowserShopLink extends StatefulWidget {
  const _BrowserShopLink({
    required this.route,
    required this.label,
    required this.child,
    required this.onNavigate,
    required this.focusColor,
  });
  final Uri route;
  final String label;
  final Widget child;
  final VoidCallback onNavigate;
  final Color focusColor;
  @override
  State<_BrowserShopLink> createState() => _BrowserShopLinkState();
}

class _BrowserShopLinkState extends State<_BrowserShopLink> {
  final focus = FocusNode(debugLabel: 'Shop browser link');
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    includeSemantics: false,
    onFocusChange: (focused) {
      if (mounted) setState(() {});
      if (focused) Scrollable.ensureVisible(context, alignment: .5);
    },
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.space,
          ].contains(event.logicalKey)) {
        widget.onNavigate();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Semantics(
      container: true,
      link: true,
      linkUrl: Uri.base.replace(fragment: widget.route.toString()),
      label: widget.label,
      focusable: true,
      focused: focus.hasFocus,
      onFocus: focus.requestFocus,
      onTap: widget.onNavigate,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 2,
            color: focus.hasFocus ? widget.focusColor : Colors.transparent,
          ),
        ),
        child: ExcludeFocus(child: ExcludeSemantics(child: widget.child)),
      ),
    ),
  );
}
