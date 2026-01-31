import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🔥 Troonky Logo Widget (Reusable Everywhere)
class TroonkyLogo extends StatelessWidget {
  final double size;
  final bool showText;

  const TroonkyLogo({
    super.key,
    this.size = 32,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        /// Gradient Circle Logo
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Color(0xFF6A11CB), // Purple
                Color(0xFF2575FC), // Blue
                Color(0xFFFF416C), // Pink/Red
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(Icons.play_arrow,
              color: Colors.white, size: size * 0.6),
        ),

        /// Spacing + Text (optional)
        if (showText) ...[
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFF6A11CB),
                Color(0xFF2575FC),
                Color(0xFFFF416C),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              "Troonky",
              style: GoogleFonts.poppins(
                fontSize: size * 0.7,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ),
        ]
      ],
    );
  }
}
