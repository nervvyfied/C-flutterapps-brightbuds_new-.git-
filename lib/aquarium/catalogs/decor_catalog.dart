import '../models/decor_definition.dart'; // your class

class DecorCatalog {
  static final List<DecorDefinition> all = [
    DecorDefinition(id: 'decor1', name: 'Blue Seaweed', assetPath: 'assets/decorations/decor1.png', price: 50, description: 'Swaying blue seaweed.'),
    DecorDefinition(id: 'decor2', name: 'Purple Seaweed', assetPath: 'assets/decorations/decor2.png', price: 55, description: 'Pretty purple fronds.'),
    DecorDefinition(id: 'decor3', name: 'Seaweed', assetPath: 'assets/decorations/decor3.png', price: 45, description: 'Simple seaweed.'),
    DecorDefinition(id: 'decor4', name: 'Orange Coral', assetPath: 'assets/decorations/decor4.png', price: 70, description: 'Bright coral.'),
    DecorDefinition(id: 'decor5', name: 'Rock 1', assetPath: 'assets/decorations/decor5.png', price: 30, description: 'Round rock.'),
    DecorDefinition(id: 'decor6', name: 'Rock 2', assetPath: 'assets/decorations/decor6.png', price: 35, description: 'Smooth rock.'),
    DecorDefinition(id: 'decor7', name: 'Pink Seaweed', assetPath: 'assets/decorations/decor7.png', price: 60, description: 'Pink seaweed.'),
    DecorDefinition(id: 'decor8', name: 'Pink Coral', assetPath: 'assets/decorations/decor8.png', price: 75, description: 'Delicate coral.'),
    DecorDefinition(id: 'decor9', name: 'Crystal Coral', assetPath: 'assets/decorations/decor9.png', price: 90, description: 'Shimmery coral.'),
    DecorDefinition(id: 'decor10', name: 'Yellow Coral', assetPath: 'assets/decorations/decor10.png', price: 65, description: 'Sunny coral.'),
    DecorDefinition(id: 'decor11', name: 'Treasure Chest', assetPath: 'assets/decorations/decor11.png', price: 120, description: 'A chest!'),
    DecorDefinition(id: 'decor12', name: 'Sandcastle', assetPath: 'assets/decorations/decor12.png', price: 80, description: 'A tiny sandcastle.'),
  ];

  static DecorDefinition byId(String id) {
    return all.firstWhere((d) => d.id == id, orElse: () {
      throw Exception('Decor with id $id not found');
    });
  }
}
