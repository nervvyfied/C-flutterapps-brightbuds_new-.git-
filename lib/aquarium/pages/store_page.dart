import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/decor_provider.dart';
import '../providers/fish_provider.dart';
import '../catalogs/decor_catalog.dart';
import '../catalogs/fish_catalog.dart';
import '../../data/providers/auth_provider.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  int selectedTab = 0; // 0 = Decors, 1 = Fishes

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store')),
      body: Consumer3<DecorProvider, FishProvider, AuthProvider>(
        builder: (context, decorProvider, fishProvider, authProvider, _) {
          final balance = fishProvider.currentChild.balance;

          Widget coinPrice(int price) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/coin.png', height: 20),
                const SizedBox(width: 4),
                Text(
                  '$price',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            );
          }

          return Stack(
            children: [
              // ✅ Background image
              Positioned.fill(
                child: Image.asset(
                  'assets/store_bg.png',
                  fit: BoxFit.cover,
                ),
              ),

              // ✅ Store content
              SingleChildScrollView(
                child: Column(
                  children: [
                    // ----- BALANCE -----
                    Container(
                      padding: const EdgeInsets.all(12),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Balance: ",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Image.asset('assets/coin.png', height: 24),
                          const SizedBox(width: 4),
                          Text(
                            '$balance',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    // ----- TABS -----
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTabButton("Decors", 0),
                          const SizedBox(width: 10),
                          _buildTabButton("Fishes", 1),
                        ],
                      ),
                    ),

                    // ----- STORE CONTENT -----
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: selectedTab == 0
                          ? _buildDecorGrid(
                              decorProvider, fishProvider, balance, coinPrice)
                          : _buildFishGrid(
                              fishProvider, balance, coinPrice),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- TAB BUTTON BUILDER ----------------
  Widget _buildTabButton(String label, int index) {
    final bool isSelected = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFA6C26F)
                : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black87,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- DECOR GRID ----------------
  Widget _buildDecorGrid(DecorProvider decorProvider,
      FishProvider fishProvider, int balance, Widget Function(int) coinPrice) {
    return GridView.builder(
      key: const ValueKey("DecorGrid"),
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
        final canAfford = balance >= decor.price;

        return _frostedCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Image.asset(decor.assetPath, height: 100),
              Text(decor.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              coinPrice(decor.price),
              ElevatedButton(
                onPressed:
                    (!alreadyPlaced && (canAfford || ownedButNotPlaced))
                        ? () async {
                            bool success = false;

                            if (ownedButNotPlaced) {
                              success = await decorProvider.placeFromInventory(
                                  decor.id, 100, 100);
                              if (!success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("Failed to place decor")),
                                );
                                return;
                              }
                            } else {
                              success =
                                  await decorProvider.purchaseDecor(decor);
                              if (!success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Not enough balance or already placed")),
                                );
                                return;
                              }
                            }

                            fishProvider.refresh();
                          }
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford || ownedButNotPlaced
                      ? const Color(0xFFA6C26F)
                      : const Color(0xFFFD5C68),
                ),
                child: Text(
                  ownedButNotPlaced
                      ? "Place"
                      : alreadyPlaced
                          ? "Already Placed"
                          : "Buy",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- FISH GRID ----------------
  Widget _buildFishGrid(FishProvider fishProvider, int balance,
      Widget Function(int) coinPrice) {
    return GridView.builder(
      key: const ValueKey("FishGrid"),
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

        return _frostedCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Image.asset(fish.storeIconAsset, height: 100),
              Text(fish.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              coinPrice(fish.price),
              ElevatedButton(
                onPressed: (!owned && canAfford)
                    ? () async {
                        final success =
                            await fishProvider.purchaseFish(fish);
                        if (!success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  "Not enough balance or already owned"),
                            ),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford || owned
                      ? const Color(0xFFA6C26F)
                      : const Color(0xFFFD5C68),
                ),
                child: Text(
                  owned ? "Owned" : "Buy",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- FROSTED CARD EFFECT ----------------
  Widget _frostedCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}
