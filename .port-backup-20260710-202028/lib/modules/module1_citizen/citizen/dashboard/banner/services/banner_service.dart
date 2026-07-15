import 'package:flutter/material.dart';

import '../models/banner_slide.dart';

class BannerService {
  const BannerService();

  Future<List<BannerSlide>> loadCached() async {
    return const [];
  }

  Future<List<BannerSlide>> fetchRemote() async {
    return const [
      BannerSlide(
        chipLabel: 'IWMS',
        title: 'Track collections',
        subtitle: 'Monitor daily waste collection activity from the app.',
        colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
        icon: Icons.map_outlined,
        backgroundImage: 'assets/banner/banner1.jpg',
      ),
      BannerSlide(
        chipLabel: 'SERVICE',
        title: 'Raise grievances',
        subtitle: 'Report local waste issues and follow the ticket status.',
        colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
        icon: Icons.support_agent,
        backgroundImage: 'assets/banner/banner2.jpg',
      ),
      BannerSlide(
        chipLabel: 'CLEAN',
        title: 'Segregate waste',
        subtitle: 'Keep dry, wet, and mixed waste separated at source.',
        colors: [Color(0xFF00695C), Color(0xFF26A69A)],
        icon: Icons.eco_outlined,
        backgroundImage: 'assets/banner/banner3.jpg',
      ),
    ];
  }
}
