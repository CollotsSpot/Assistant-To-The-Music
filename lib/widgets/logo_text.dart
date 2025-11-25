import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LogoText extends StatelessWidget {
  final double fontSize;
  final bool lightMode;

  const LogoText({
    super.key, 
    this.fontSize = 24, 
    this.lightMode = false
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = lightMode ? Colors.white : colorScheme.onBackground;
    
    return Text(
      'Assistant To The Music',
      style: GoogleFonts.specialElite(
        textStyle: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          // Typewriter fonts often don't need extra letter spacing
          shadows: [
            Shadow(
              color: colorScheme.primary.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
