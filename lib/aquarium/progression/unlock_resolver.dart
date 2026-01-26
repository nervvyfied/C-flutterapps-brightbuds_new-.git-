import '../models/fish_definition.dart';
import '../models/decor_definition.dart';
import '../catalogs/fish_catalog.dart';
import '../catalogs/decor_catalog.dart';
import 'world_progression.dart';

class UnlockResolver {
  final int currentLevel;
  final int currentWorld;

  UnlockResolver({required this.currentLevel, required this.currentWorld});

  List<FishDefinition> get unlockedFish {
    return FishCatalog.all.where((fish) {
      return fish.world == currentWorld && fish.unlockLevel <= currentLevel;
    }).toList();
  }

  List<DecorDefinition> get unlockedDecor {
    return DecorCatalog.all.where((decor) {
      return decor.world == currentWorld && decor.unlockLevel <= currentLevel;
    }).toList();
  }
}
