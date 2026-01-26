import '../models/fish_definition.dart';

class FishCatalog {
  static final List<FishDefinition> all = [
    // ----- World 1: Aquarium -----
    FishDefinition(
      id: "fish3",
      name: "Blue Fish",
      world: 1,
      unlockLevel: 3,
      normalAsset: 'assets/fish/normal/fish1_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish1_neglected.png',
      layer: 1,
      description: "Your very first fish! A simple blue fish to start your journey.",
    ),
    FishDefinition(
      id: "fish5",
      name: "Goldfish",
      world: 1,
      unlockLevel: 5,
      normalAsset: 'assets/fish/normal/fish5_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish5_neglected.png',
      layer: 1,
      description: "A classic goldfish that’s always a favorite!",
    ),
    FishDefinition(
      id: "fish6",
      name: "Pufferfish",
      world: 1,
      unlockLevel: 7,
      normalAsset: 'assets/fish/normal/fish6_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish6_neglected.png',
      layer: 2,
      description: "Complete 50 tasks and puff up with pride!",
    ),
    FishDefinition(
      id: "fish11",
      name: "Turtle",
      world: 1,
      unlockLevel: 9,
      normalAsset: 'assets/fish/normal/fish11_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish11_neglected.png',
      layer: 2,
      description: "Place 5 decorations! Steady caretaker vibes.",
    ),
    FishDefinition(
      id: "fish7",
      name: "Clownfish",
      world: 1,
      unlockLevel: 11,
      normalAsset: 'assets/fish/normal/fish7_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish7_neglected.png',
      layer: 2,
      description: "A playful clownfish, guaranteed to make you smile.",
    ),

    // ----- World 2: Pond -----
    FishDefinition(
      id: "fish2",
      name: "Green Fish",
      world: 2,
      unlockLevel: 15,
      normalAsset: 'assets/fish/normal/fish2_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish2_neglected.png',
      layer: 1,
      description: "A cheerful green fish ready to brighten up your pond!",
    ),
    FishDefinition(
      id: "fish3_red",
      name: "Red Fish",
      world: 2,
      unlockLevel: 17,
      normalAsset: 'assets/fish/normal/fish3_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish3_neglected.png',
      layer: 1,
      description: "A fiery red fish to add some spice to your pond.",
    ),
    FishDefinition(
      id: "fish4",
      name: "Pink Fish",
      world: 2,
      unlockLevel: 19,
      normalAsset: 'assets/fish/normal/fish4_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish4_neglected.png',
      layer: 1,
      description: "A cute pink fish that loves to swim in style.",
    ),
    FishDefinition(
      id: "fish8",
      name: "Rainbow Trout",
      world: 2,
      unlockLevel: 21,
      normalAsset: 'assets/fish/normal/fish8_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish8_neglected.png',
      layer: 2,
      description: "A colorful green fish that stands out from the crowd!",
    ),
    FishDefinition(
      id: "fish9",
      name: "Angelfish",
      world: 2,
      unlockLevel: 23,
      normalAsset: 'assets/fish/normal/fish9_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish9_neglected.png',
      layer: 2,
      description: "A graceful angelfish, gliding elegantly through your pond.",
    ),
    FishDefinition(
      id: "fish10",
      name: "Surgeonfish",
      world: 2,
      unlockLevel: 24,
      normalAsset: 'assets/fish/normal/fish10_normal.gif',
      neglectedAsset: 'assets/fish/neglected/fish10_neglected.png',
      layer: 2,
      description: "A forgetful but fun fish who’s always ready for adventure!",
    ),
  ];

  static FishDefinition byId(String id) {
    return all.firstWhere((f) => f.id == id, orElse: () {
      throw Exception('Fish with id $id not found');
    });
  }

  static List<FishDefinition> byWorld(int world) =>
      all.where((f) => f.world == world).toList();

  static List<FishDefinition> byLevel(int level) =>
      all.where((f) => f.unlockLevel <= level).toList();
}
