import 'package:brightbuds_new/aquarium/models/fish_definition.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../providers/fish_provider.dart';
import '../catalogs/decor_catalog.dart';
import '../catalogs/fish_catalog.dart';

class InventoryModal extends StatelessWidget {
  const InventoryModal({super.key});

  @override
  Widget build(BuildContext context) {
    final decorProvider = context.watch<DecorProvider>();
    final fishProvider = context.watch<FishProvider>();
    final inactiveFishes = fishProvider.ownedFishes.where((fish) => !fish.isActive).toList();
    final allFishes = fishProvider.ownedFishes;


    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text("Your Inventory",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),

                // ----- DECORS -----
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Decors",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: decorProvider.inventory.length,
                  itemBuilder: (context, index) {
                    final decor = decorProvider.inventory[index];
                    final def = DecorCatalog.byId(decor.decorId);

                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context,decor);
                      },
                      child: Column(
                        children: [
                          Expanded(child: Image.asset(def.assetPath)),
                          Text(def.name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),

                // ----- FISH -----
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Fishes",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  padding: const EdgeInsets.all(12),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
  ),
  itemCount: allFishes.length,
  itemBuilder: (context, index) {
    final fish = allFishes[index];
    final def = FishCatalog.byId(fish.fishId);

    return Column(
      children: [
        Expanded(child: Image.asset(def.storeIconAsset)),
        Text(def.name, style: const TextStyle(fontSize: 12)),
        if (fish.isActive) 
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.inventory),
                onPressed: () => fishProvider.storeFish(fish.fishId),
              ),
              if (def.type == FishType.purchasable) // ✅ only show sell for purchasable
              IconButton(
                icon: const Icon(Icons.attach_money),
                onPressed: () => fishProvider.sellFish(fish.fishId),
              ),
            ],
          )
        else
          ElevatedButton(
            onPressed: () => fishProvider.activateFish(fish.fishId),
            child: const Text("Place"),
          ),
      ],
    );
  },
)

              ],
            ),
          ),
        );
      },
    );
  }
}
