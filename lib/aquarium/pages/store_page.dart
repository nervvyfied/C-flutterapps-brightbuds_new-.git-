import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../providers/fish_provider.dart';
import '../catalogs/decor_catalog.dart';
import '../catalogs/fish_catalog.dart';

class StorePage extends StatelessWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final decorProvider = context.watch<DecorProvider>();
    final fishProvider = context.watch<FishProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Store')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Balance at top
            Container(
              padding: const EdgeInsets.all(12),
              alignment: Alignment.centerLeft,
              child: Text(
                'Balance: \$${decorProvider.currentChild.balance}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            // ----- DECOR STORE -----
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text("Decors",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: DecorCatalog.all.length,
              itemBuilder: (context, index) {
                final decor = DecorCatalog.all[index];
                final alreadyPlaced = decorProvider.isAlreadyPlaced(decor.id);
                final ownedButNotPlaced =
                    decorProvider.isOwnedButNotPlaced(decor.id);
                final canAfford = decorProvider.currentChild.balance >= decor.price;

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Image.asset(decor.assetPath, height: 100),
                      Text(decor.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('\$${decor.price}'),
                      ElevatedButton(
                        onPressed: alreadyPlaced
                            ? null
                            : () async {
                                if (ownedButNotPlaced) {
                                  await decorProvider
                                      .openEditModeForPlacement(decor.id);
                                  Navigator.pop(context);
                                  return;
                                }

                                final success =
                                    await decorProvider.purchaseDecor(decor);
                                if (!success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Not enough balance or already placed")),
                                  );
                                  return;
                                }

                                final placeNow = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text("Place Decor?"),
                                    content: const Text(
                                        "Do you want to place this decor now?"),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text("No")),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text("Yes")),
                                    ],
                                  ),
                                );

                                if (placeNow == true) {
                                  await decorProvider
                                      .openEditModeForPlacement(decor.id);
                                  Navigator.pop(context);
                                }
                              },
                        child: Text(
                          ownedButNotPlaced
                              ? "Place"
                              : alreadyPlaced
                                  ? "Already Placed"
                                  : "Buy",
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ----- FISH STORE -----
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text("Fishes",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: FishCatalog.purchasables.length,
              itemBuilder: (context, index) {
                final fish = FishCatalog.purchasables[index];
                final owned = fishProvider.isOwned(fish.id);
                final unlocked = fishProvider.isUnlocked(fish.id);
                final canAfford = decorProvider.currentChild.balance >= fish.price;

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Image.asset(fish.storeIconAsset, height: 100),
                      Text(fish.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('\$${fish.price}'),
                      ElevatedButton(
                        onPressed: owned
                            ? null
                            : () async {
                                final success = await fishProvider.purchaseFish(fish);
                                if (!success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Not enough balance or already owned")),
                                  );
                                }
                              },
                        child: Text(
                          owned ? "Owned" : "Buy",
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
