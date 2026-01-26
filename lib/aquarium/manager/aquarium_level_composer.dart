import 'package:brightbuds_new/aquarium/catalogs/decor_catalog.dart';
import 'package:brightbuds_new/aquarium/catalogs/fish_catalog.dart';
import 'package:flutter/material.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';

class AquariumLevelComposer {
  static LevelData getLevelData({
    required int level,
    required int world,
  }) {
    final fishes = FishCatalog.all
        .where((f) => f.world == world && f.unlockLevel <= level)
        .toList();

    final decors = DecorCatalog.all
        .where((d) => d.world == world && d.unlockLevel <= level)
        .toList();

    final decorData = decors
    .map((d) => DecorData(
          asset: d.assetPath,
          anchorX: d.anchorX,
          anchorY: d.anchorY,
          layer: d.layer,
          widthFactor: d.widthFactor,
        ))
    .toList();

return LevelData(fishes: fishes, decors: decorData);
  }
}

class LevelData {
  final List<FishDefinition> fishes;
  final List<DecorData> decors;

  LevelData({required this.fishes, required this.decors});
}

class DecorData {
  final String asset;
  final double anchorX;
  final double anchorY;
  final int layer;
  final double widthFactor;

  DecorData({required this.asset, required this.anchorX, required this.anchorY ,required this.layer, required this.widthFactor});
}
