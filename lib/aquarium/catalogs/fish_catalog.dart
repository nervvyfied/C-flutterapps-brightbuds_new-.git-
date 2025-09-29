import '../models/fish_definition.dart'; // adjust path as needed

class FishCatalog {
  static final List<FishDefinition> all = [
  // ----- Unlockable Fishes -----
  FishDefinition(
    id: "fish1",
    name: "Blue Fish",
    normalAsset: 'assets/fish/normal/fish1_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish1_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish1_icon.png',
    type: FishType.unlockable,
    unlockConditionId: "first_aquarium_visit",
    description: "Your very first fish! A simple blue fish to start your journey.",
  ),
  FishDefinition(
    id: "fish6",
    name: "Pufferfish",
    normalAsset: 'assets/fish/normal/fish6_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish6_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish6_icon.png',
    type: FishType.unlockable,
    unlockConditionId: "task_milestone_50",
    description: "Complete 50 tasks and puff up with pride!",
  ),
  FishDefinition(
    id: "fish11",
    name: "Turtle",
    normalAsset: 'assets/fish/normal/fish11_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish11_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish11_icon.png',
    type: FishType.unlockable,
    unlockConditionId: "place_5_decor",
    description: "Place 5 decorations! Steady caretaker vibes.",
  ),
  FishDefinition(
    id: "fish12",
    name: "Red Seahorse",
    normalAsset: 'assets/fish/normal/fish12_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish12_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish12_icon.png',
    type: FishType.unlockable,
    unlockConditionId: "complete_10_hard_tasks",
    description: "Complete 10 hard tasks! Strong and resilient like a seahorse.",
  ),

  // ----- Purchasable Fishes -----
  FishDefinition(
    id: "fish2",
    name: "Green Fish",
    normalAsset: 'assets/fish/normal/fish2_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish2_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish2_icon.png',
    type: FishType.purchasable,
    price: 50,
    description: "A cheerful green fish ready to brighten up your aquarium!",
  ),
  FishDefinition(
    id: "fish3",
    name: "Red Fish",
    normalAsset: 'assets/fish/normal/fish3_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish3_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish3_icon.png',
    type: FishType.purchasable,
    price: 75,
    description: "A fiery red fish to add some spice to your tank.",
  ),
  FishDefinition(
    id: "fish4",
    name: "Pink Fish",
    normalAsset: 'assets/fish/normal/fish4_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish4_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish4_icon.png',
    type: FishType.purchasable,
    price: 60,
    description: "A cute pink fish that loves to swim in style.",
  ),
  FishDefinition(
    id: "fish5",
    name: "Goldfish",
    normalAsset: 'assets/fish/normal/fish5_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish5_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish5_icon.png',
    type: FishType.purchasable,
    price: 80,
    description: "A classic goldfish that’s always a favorite!",
  ),
  FishDefinition(
    id: "fish7",
    name: "Clownfish",
    normalAsset: 'assets/fish/normal/fish7_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish7_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish7_icon.png',
    type: FishType.purchasable,
    price: 70,
    description: "A playful clownfish, guaranteed to make you smile.",
  ),
  FishDefinition(
    id: "fish8",
    name: "Rainbow Trout",
    normalAsset: 'assets/fish/normal/fish8_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish8_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish8_icon.png',
    type: FishType.purchasable,
    price: 65,
    description: "A colorful green fish that stands out from the crowd!",
  ),
  FishDefinition(
    id: "fish9",
    name: "Angelfish",
    normalAsset: 'assets/fish/normal/fish9_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish9_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish9_icon.png',
    type: FishType.purchasable,
    price: 90,
    description: "A graceful angelfish, gliding elegantly through your tank.",
  ),
  FishDefinition(
    id: "fish10",
    name: "Surgeonfish",
    normalAsset: 'assets/fish/normal/fish10_normal.gif',
    neglectedAsset: 'assets/fish/neglected/fish10_neglected.png',
    storeIconAsset: 'assets/fish/icon/fish10_icon.png',
    type: FishType.purchasable,
    price: 85,
    description: "A forgetful but fun fish who’s always ready for adventure!",
  ),
];

static List<FishDefinition> get purchasables =>
      all.where((f) => f.type == FishType.purchasable).toList();

  static List<FishDefinition> get unlockables =>
      all.where((f) => f.type == FishType.unlockable).toList();

static FishDefinition byId(String id) {
    return all.firstWhere((f) => f.id == id,
        orElse: () => throw Exception('Fish with id $id not found'));
  }
}