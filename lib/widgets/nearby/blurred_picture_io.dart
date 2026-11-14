import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// [url]'s picture, heavily blurred, filling its box (for the
/// sensitive-content cover).
Widget blurredPicture(String url) => ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const SizedBox.shrink()),
    );
