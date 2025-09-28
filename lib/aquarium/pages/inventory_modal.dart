import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../catalogs/decor_catalog.dart';

class InventoryModal extends StatelessWidget {
  const InventoryModal({super.key});

  @override
  Widget build(BuildContext context) {
    final decorProvider = Provider.of<DecorProvider>(context);

    final inventory = decorProvider.inventory;

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
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("Your Inventory",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Expanded(
              child: Consumer<DecorProvider>(
                builder: (context, decorProvider, _) {
                  final inventory = decorProvider.inventory;

                  return GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: inventory.length,
                    itemBuilder: (context, index) {
                      final decor = inventory[index];
                      final def = DecorCatalog.byId(decor.decorId);

                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context, decor); // return selected
                        },
                        child: Column(
                          children: [
                            Expanded(child: Image.asset(def.assetPath)),
                            Text(def.name, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            ],
          ),
        );
      },
    );
  }
}
