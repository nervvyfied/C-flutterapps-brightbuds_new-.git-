import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../catalogs/decor_catalog.dart';

class DecorStorePage extends StatelessWidget {
  const DecorStorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final decorProvider = Provider.of<DecorProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Decor Store')),
      body: Column(
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
          Expanded(
            child: GridView.builder(
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
                      Text(decor.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('\$${decor.price}'),
                      ElevatedButton(
                        onPressed: alreadyPlaced
                            ? null
                            : () async {
                                if (ownedButNotPlaced) {
                                  // Place from inventory -> open aquarium edit mode focusing that decor
                                  await decorProvider.openEditModeForPlacement(decor.id);
                                  Navigator.pop(context); // back to aquarium (which is in edit mode)
                                  return;
                                }

                                // Attempt to purchase (adds to inventory)
                                final success = await decorProvider.purchaseDecor(decor);
                                if (!success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Not enough balance or already placed")),
                                  );
                                  return;
                                }

                                // After purchase, ask whether to place now (which opens edit mode)
                                final placeNow = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text("Place Decor?"),
                                    content: const Text("Do you want to place this decor now?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text("No"),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text("Yes"),
                                      ),
                                    ],
                                  ),
                                );

                                if (placeNow == true) {
                                  // Open aquarium edit mode focusing the newly purchased decor
                                  await decorProvider.openEditModeForPlacement(decor.id);
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ownedButNotPlaced
                              ? Colors.orange
                              : alreadyPlaced
                                  ? Colors.grey
                                  : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
