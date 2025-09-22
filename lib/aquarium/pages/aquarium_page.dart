import 'package:flutter/material.dart';

class AquariumPage extends StatefulWidget {
  const AquariumPage({super.key});

  @override
  State<AquariumPage> createState() => _AquariumPageState();
}

class _AquariumPageState extends State<AquariumPage> {
  double offsetX = 0.0;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      offsetX += details.delta.dx;
      // Limit the movement to prevent excessive scrolling
      offsetX = offsetX.clamp(-50.0, 50.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        child: Stack(
          children: [
            // Static water background
            Positioned.fill(
              child: Image.asset(
                'assets/tank/water_bg.png',
                fit: BoxFit.cover,
              ),
            ),
            // Distant sand background - moves very slightly
            Positioned.fill(
              left: offsetX * 0.2,
              right: -offsetX * 0.2,
              child: Image.asset(
                'assets/tank/sand_bg.png',
                fit: BoxFit.cover,
              ),
            ),
            // Sand1 - moves more
            Positioned.fill(
              left: offsetX * 0.5,
              right: -offsetX * 0.5,
              child: Image.asset(
                'assets/tank/sand1.png',
                fit: BoxFit.cover,
              ),
            ),
            // Sand2 - foreground, moves the most
            Positioned.fill(
              left: offsetX * 0.8,
              right: -offsetX * 0.8,
              child: Image.asset(
                'assets/tank/sand2.png',
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
