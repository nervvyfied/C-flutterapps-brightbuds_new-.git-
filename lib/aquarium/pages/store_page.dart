import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../providers/fish_provider.dart';
import '../catalogs/decor_catalog.dart';
import '../catalogs/fish_catalog.dart';
import '../../data/providers/auth_provider.dart';

class StorePage extends StatelessWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store')),
      body: Consumer3<DecorProvider, FishProvider, AuthProvider>(
        builder: (context, decorProvider, fishProvider, authProvider, _) {
          // ✅ Use the balance from FishProvider, not AuthProvider
          final balance = fishProvider.currentChild.balance;

          return SingleChildScrollView(
            child: Column(
              children: [
                // ----- BALANCE -----
                Container(
                  padding: const EdgeInsets.all(12),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Balance: \$$balance",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),

                // ----- DECOR STORE -----
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    "Decors",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
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
                    final ownedButNotPlaced = decorProvider.isOwnedButNotPlaced(decor.id);
                    final canAfford = balance >= decor.price;

                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Image.asset(decor.assetPath, height: 100),
                          Text(decor.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('\$${decor.price}'),
                          ElevatedButton(
                            onPressed: (!alreadyPlaced && (canAfford || ownedButNotPlaced))
                                ? () async {
                                    if (ownedButNotPlaced) {
                                      final success = await decorProvider.placeFromInventory(decor.id, 100, 100);
                                      if (!success) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Failed to place decor")),
                                        );
                                      }
                                      return;
                                    }

                                    final success = await decorProvider.purchaseDecor(decor);
                                    if (!success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Not enough balance or already placed"),
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                : null,
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
                  child: Text(
                    "Fishes",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
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
                    final canAfford = balance >= fish.price;

                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Image.asset(fish.storeIconAsset, height: 100),
                          Text(fish.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('\$${fish.price}'),
                          ElevatedButton(
                            onPressed: (!owned && canAfford)
                                ? () async {
                                    final success = await fishProvider.purchaseFish(fish);
                                    if (!success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Not enough balance or already owned"),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            child: Text(owned ? "Owned" : "Buy"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
