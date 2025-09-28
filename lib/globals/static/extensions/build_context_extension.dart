import 'package:flutter/material.dart';

/// snack bar for all content

extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message, overflow: TextOverflow.fade),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).snackBarTheme.backgroundColor,
      ),
    );
  }

  /// BuildContext extension <p>
  /// Pushes an animated popup to the NavigatorState of the BuildContext
  Future<void> pushPopup(Widget widget, {Offset? begin}) async {
    // Pushes the popup to the app navigator
    await Navigator.of(this).push(PageRouteBuilder(
      // See-through 'page'
      // Builds the popup; creates separate instance of BuildContext
      pageBuilder: (context, _, __) {
        return widget;
      },
      // Manages animation
      transitionsBuilder: (context, a1, a2, child) {
        // Page begins 1 page to the left of the visible screen; slides onto screen
        begin ??= const Offset(-1.0, 0.0);
        const Offset end = Offset.zero;
        const Curve curve = Curves.easeInOut;

        // Animation 'Tween' which manages popup movement
        final Animatable<Offset> slideTween =
        Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        // Tween which handles the background fading to 50% opacity black
        final Tween<double> fadeTween = Tween(begin: 0.0, end: 1.0);

        // Stacks the sliding animation on top of the fading animation
        return Stack(
          children: [
            // Container (50% opacity black) follows fade in animation
            FadeTransition(
              opacity: a1.drive(fadeTween),
              child: GestureDetector(
                onTap: () {
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  }
                },
                // Listens for swipe in opposite direction of animation to dismiss popup
                onHorizontalDragEnd: (detail){
                  if(detail.primaryVelocity!.sign == begin!.dx.sign && Navigator.canPop(context)){
                    Navigator.of(context).pop();
                  }
                },
                onVerticalDragEnd: (detail){
                  if(detail.primaryVelocity!.sign == begin!.dy.sign && Navigator.canPop(context)){
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  color: Colors.black.withValues(alpha: 0.75),
                ),
              ),
            ),
            // Popup follows sliding animation
            SlideTransition(
              position: a1.drive(slideTween),
              child: child,
            ),
          ],
        );
      },
    ));
  }
}
