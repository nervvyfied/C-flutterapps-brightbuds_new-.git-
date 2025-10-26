import 'dart:async';
import 'dart:collection';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fish_definition.dart';
import '../models/ownedFish_model.dart';
import '../repositories/fish_repository.dart';
import '../catalogs/fish_catalog.dart';
import '/data/models/child_model.dart';
import '../../data/providers/auth_provider.dart';

class FishProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final FishRepository _repo = FishRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late ChildUser currentChild;
  late Box<ChildUser> _childBox;

  List<OwnedFish> ownedFishes = [];
  List<OwnedFish> _editingBuffer = [];
  bool isInEditMode = false;
  String? movingFishId;

  StreamSubscription<DocumentSnapshot>? _balanceListener;
  StreamSubscription<BoxEvent>? _hiveWatchSub;

  Function(int newBalance)? onBalanceChanged;

  FishProvider({required this.authProvider}) {
    _childBox = Hive.box<ChildUser>('childBox');

    if (authProvider.currentUserModel is ChildUser) {
      currentChild = authProvider.currentUserModel as ChildUser;

      final child = authProvider.currentUserModel;
      if (child is ChildUser) {
        // start listening to firestore balance changes
        listenToChildBalance(child.parentUid, child.cid);
      }

      // Delay slightly to ensure Hive is fully ready before restore
      Future.delayed(const Duration(milliseconds: 300), () async {
        await _restoreFromHive();

        // small delay before remote init to avoid race conditions
        await Future.delayed(const Duration(milliseconds: 300));
        await _init();

        // Hive watch — unsubscribe previous if any, then watch for updates to this child key
        await _hiveWatchSub?.cancel();
        _hiveWatchSub = _childBox.watch(key: currentChild.cid).listen((event) {
          try {
            // event.value may be null when deleted - guard it
            final dynamic val = event.value;
            if (val == null) return;
            if (val is ChildUser) {
              final updatedChild = val;
              if (updatedChild.balance != currentChild.balance) {
                currentChild = currentChild.copyWith(
                  balance: updatedChild.balance,
                );
                notifyListeners();
                if (kDebugMode) {
                  print(
                    "🔄 Hive sync: balance updated to ${currentChild.balance}",
                  );
                }
              }
            } else if (val is Map) {
              // If your Hive stores maps, convert
              final updatedChild = ChildUser.fromMap(
                Map<String, dynamic>.from(val),
                currentChild.cid,
              );
              if (updatedChild.balance != currentChild.balance) {
                currentChild = currentChild.copyWith(
                  balance: updatedChild.balance,
                );
                notifyListeners();
                if (kDebugMode) {
                  print(
                    "🔄 Hive sync (map): balance updated to ${currentChild.balance}",
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ Hive watch handler error: $e');
          }
        });
      });
    }
  }

  /// Listen for realtime balance updates from Firestore and update currentChild.balance
  void listenToChildBalance(String parentId, String childId) {
    // cancel previous listener if any
    _balanceListener?.cancel();

    try {
      final docRef = _firestore
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId);

      _balanceListener = docRef.snapshots().listen(
        (snapshot) async {
          try {
            if (!snapshot.exists) return;
            final data = snapshot.data();
            if (data == null) return;

            // Robust parse of balance -> int
            final dynamic rawBalance = data['balance'];
            final int newBalance = _parseBalance(rawBalance);

            if (newBalance != currentChild.balance) {
              // Update provider state from authoritative Firestore value
              if (kDebugMode)
                debugPrint('🔁 Balance updated in Firestore: $newBalance');

              currentChild = currentChild.copyWith(balance: newBalance);

              // persist to Hive (if child exists)
              try {
                final child = _childBox.get(currentChild.cid);
                if (child != null) {
                  final updatedChild = child.copyWith(balance: newBalance);
                  await _childBox.put(currentChild.cid, updatedChild);
                }
              } catch (e) {
                debugPrint('⚠️ Failed to persist balance to Hive: $e');
              }

              notifyListeners();
              onBalanceChanged?.call(newBalance);
            }
          } catch (e) {
            debugPrint('⚠️ Balance listener handler error: $e');
          }
        },
        onError: (e) {
          debugPrint('⚠️ Balance listener error: $e');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Failed to start balance listener: $e');
    }
  }

  int _parseBalance(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is String) {
      return int.tryParse(raw) ?? (double.tryParse(raw)?.toInt() ?? 0);
    }
    return 0;
  }

  @override
  void dispose() {
    _balanceListener?.cancel();
    _hiveWatchSub?.cancel();
    super.dispose();
  }

  // ---------- Restore from Hive ----------
  Future<void> _restoreFromHive() async {
    // Ensure box is open and currentChild is valid
    if (!_childBox.isOpen || !_childBox.containsKey(currentChild.cid)) {
      if (kDebugMode) print("⚠️ No Hive data found for ${currentChild.cid}");
      notifyListeners(); // still rebuild UI even if empty
      return;
    }

    final child = _childBox.get(currentChild.cid);
    if (child != null) {
      // Restore balance
      currentChild = currentChild.copyWith(balance: child.balance);

      // Restore owned fishes
      try {
        ownedFishes = child.ownedFish
            .map((map) => OwnedFish.fromMap(Map<String, dynamic>.from(map)))
            .toList();
      } catch (e) {
        ownedFishes = [];
        debugPrint('⚠️ Failed to restore ownedFishes from Hive: $e');
      }

      if (kDebugMode) {
        print(
          "📦 Restored ${ownedFishes.length} fishes from Hive for ${currentChild.cid}",
        );
      }
    }

    notifyListeners(); // Always notify even if no fishes
  }

  // ---------- Initialization (remote sync) ----------
  Future<void> _init() async {
    try {
      final remoteFishes = await _repo.getOwnedFishes(
        currentChild.parentUid,
        currentChild.cid,
      );

      // Merge remote with local (avoid duplicates)
      final localIds = ownedFishes.map((f) => f.id).toSet();
      for (var fish in remoteFishes) {
        if (!localIds.contains(fish.id)) {
          ownedFishes.add(fish);
        }
      }

      notifyListeners();

      if (kDebugMode) {
        print("🌐 Synced ${ownedFishes.length} fishes from Firestore");
      }
    } catch (e) {
      if (kDebugMode) print("⚠️ Remote fetch failed, using local data: $e");
    }
  }

  Future<void> setChild(ChildUser child) async {
    currentChild = child;
    ownedFishes.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;

    await _restoreFromHive();
    await _init();

    // restart firestore listener for the new child
    listenToChildBalance(currentChild.parentUid, currentChild.cid);
  }

  // ---------- Balance ----------
  /// Update local balance, persist to Hive, and sync to remote.
  Future<void> _updateLocalBalance(int newBalance) async {
    if (currentChild.balance == newBalance) return;

    // --- Local Memory ---
    currentChild = currentChild.copyWith(balance: newBalance);

    // --- Hive Update ---
    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        await _childBox.put(
          currentChild.cid,
          child.copyWith(balance: newBalance),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update balance in Hive: $e');
    }

    notifyListeners();
    onBalanceChanged?.call(newBalance);

    // --- Firestore Update (Primary) ---
    try {
      await _firestore
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid)
          .set({'balance': newBalance}, SetOptions(merge: true));

      debugPrint('✅ Firestore balance updated directly: $newBalance');
    } catch (e) {
      debugPrint('❌ Firestore direct balance update failed: $e');
    }

    // --- Repo Backup (Ensures both Hive + Firestore match) ---
    try {
      await _repo.updateBalance(
        currentChild.parentUid,
        currentChild.cid,
        newBalance,
      );
      debugPrint('✅ Repo balance synced');
    } catch (e) {
      debugPrint('⚠️ Repo.updateBalance failed: $e');
    }

    // --- Verify & Reconcile ---
    try {
      final serverBalance = await fetchBalance(updateLocal: true);
      debugPrint(
        '🔄 Reconciled: local=${currentChild.balance}, server=$serverBalance',
      );
    } catch (e) {
      debugPrint('⚠️ Balance reconciliation failed: $e');
    }
  }

  Future<void> updateBalance(
    String parentId,
    String childId,
    int balance,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .update({'balance': balance});
  }

  /// Fetch balance from repo (remote) and optionally update local state.
  Future<int> fetchBalance({bool updateLocal = true}) async {
    try {
      final remoteBalance = await _repo.fetchBalance(
        currentChild.parentUid,
        currentChild.cid,
      );
      if (updateLocal) {
        // ensure we use provider's update flow so Hive + listeners are consistent
        if (remoteBalance != currentChild.balance) {
          currentChild = currentChild.copyWith(balance: remoteBalance);
          try {
            final child = _childBox.get(currentChild.cid);
            if (child != null) {
              final updatedChild = child.copyWith(balance: remoteBalance);
              await _childBox.put(currentChild.cid, updatedChild);
            }
          } catch (e) {
            debugPrint('⚠️ Failed to persist fetched balance to Hive: $e');
          }
          notifyListeners();
          onBalanceChanged?.call(remoteBalance);
        }
      }
      return remoteBalance;
    } catch (e) {
      debugPrint('Failed to fetch remote balance, using local: $e');
      return currentChild.balance;
    }
  }

  // ---------- Inventory ----------
  UnmodifiableListView<OwnedFish> get inventory =>
      UnmodifiableListView(ownedFishes.where((f) => !f.isActive));

  UnmodifiableListView<OwnedFish> get activeFishes =>
      UnmodifiableListView(ownedFishes.where((f) => f.isActive));

  bool isOwned(String fishId) => ownedFishes.any((f) => f.fishId == fishId);

  bool canPurchase(FishDefinition fish) =>
      fish.type == FishType.purchasable && currentChild.balance >= fish.price;

  FishDefinition getFishDefinition(String fishId) => FishCatalog.byId(fishId);

  // ---------- Purchase ----------
  Future<bool> purchaseFish(FishDefinition fish) async {
    if (!canPurchase(fish)) return false;
    if (ownedFishes.where((f) => f.fishId == fish.id).length >= 15)
      return false;

    final newFish = OwnedFish(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fishId: fish.id,
      isActive: false,
      isNeglected: false,
      isPurchased: true,
      isUnlocked: fish.type != FishType.unlockable,
    );

    final newBalance = currentChild.balance - fish.price;

    // update local & remote balance (awaited)
    await _updateLocalBalance(newBalance);

    ownedFishes.add(newFish);

    // Persist to Hive
    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        child.ownedFish.add(newFish.toMap());
        await _childBox.put(currentChild.cid, child);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to persist new fish to Hive: $e');
    }

    notifyListeners();

    // Remote sync of owned fish (use addOwnedFish which should merge)
    try {
      await _repo.addOwnedFish(
        currentChild.parentUid,
        currentChild.cid,
        newFish,
      );
    } catch (e) {
      debugPrint('⚠️ addOwnedFish failed: $e');
    }
    try {
      // Add owned fish to Firestore directly (always merge)
      final docRef = _firestore
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid)
          .collection('aquarium')
          .doc('fishes');

      await docRef.set({
        'ownedFishes': FieldValue.arrayUnion([newFish.toMap()]),
      }, SetOptions(merge: true));

      debugPrint('✅ Firestore sync success (purchaseFish)');
    } catch (e) {
      debugPrint('⚠️ Firestore sync failed (purchaseFish): $e');
    }

    if (kDebugMode) {
      print(
        "🟢 Purchased fish ${fish.name} (offline-ready, balance $newBalance)",
      );
    }

    return true;
  }

  // ---------- Activate / Store ----------
  Future<void> activateFish(String fishId) async =>
      _updateFishState(fishId, isActive: true);

  Future<void> storeFish(String fishId) async =>
      _updateFishState(fishId, isActive: false);

  Future<void> _updateFishState(String fishId, {required bool isActive}) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isActive: isActive);

    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        final updatedFishes = ownedFishes.map((f) => f.toMap()).toList();
        final updatedChild = child.copyWith(ownedFish: updatedFishes);
        await _childBox.put(currentChild.cid, updatedChild);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to persist fish state change to Hive: $e');
    }

    notifyListeners();

    try {
      await _repo.updateOwnedFish(
        currentChild.parentUid,
        currentChild.cid,
        ownedFishes[idx],
      );
    } catch (e) {
      debugPrint('⚠️ updateOwnedFish failed: $e');
    }

    if (kDebugMode)
      print(
        "🟢 Fish ${fishId} state updated: isActive=$isActive (offline-ready)",
      );
  }

  // ---------- Sell ----------
  Future<void> sellFish(String fishId) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    final fishDef = FishCatalog.byId(fishId);
    final price = fishDef.type == FishType.purchasable ? fishDef.price : 0;

    final soldFish = ownedFishes.removeAt(idx);

    if (price > 0) {
      // update local & remote balance (awaited)
      await _updateLocalBalance(currentChild.balance + price);
    }

    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        child.ownedFish.removeWhere((f) => f['id'] == soldFish.id);
        await _childBox.put(currentChild.cid, child);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to remove sold fish from Hive: $e');
    }

    try {
      await _repo.removeOwnedFish(
        currentChild.parentUid,
        currentChild.cid,
        soldFish.id,
      );
    } catch (e) {
      debugPrint('⚠️ removeOwnedFish failed: $e');
    }
    try {
      final docRef = _firestore
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid)
          .collection('aquarium')
          .doc('fishes');

      await docRef.set({
        'ownedFishes': FieldValue.arrayRemove([soldFish.toMap()]),
      }, SetOptions(merge: true));

      debugPrint('✅ Firestore sync success (sellFish)');
    } catch (e) {
      debugPrint('⚠️ Firestore sync failed (sellFish): $e');
    }

    notifyListeners();

    if (kDebugMode) {
      print(
        "🟢 Sold fish ${soldFish.fishId} for $price tokens. New balance: ${currentChild.balance}",
      );
    }
  }

  // ---------- Unlock ----------
  Future<void> unlockFish(String fishId) async {
    // if exists by id, do nothing
    if (ownedFishes.any((f) => f.id == fishId)) return;

    final newFish = OwnedFish(
      id: fishId,
      fishId: fishId,
      isUnlocked: true,
      isActive: false,
    );
    ownedFishes.add(newFish);

    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        child.ownedFish.add(newFish.toMap());
        await _childBox.put(currentChild.cid, child);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to persist unlocked fish to Hive: $e');
    }

    // Use addOwnedFish (merge-aware) to avoid overwriting remote arrays
    try {
      await _repo.addOwnedFish(
        currentChild.parentUid,
        currentChild.cid,
        newFish,
      );
    } catch (e) {
      debugPrint('⚠️ addOwnedFish (unlock) failed: $e');
    }
    try {
      final docRef = _firestore
          .collection('users')
          .doc(currentChild.parentUid)
          .collection('children')
          .doc(currentChild.cid)
          .collection('aquarium')
          .doc('fishes');

      await docRef.set({
        'ownedFishes': FieldValue.arrayUnion([newFish.toMap()]),
      }, SetOptions(merge: true));

      debugPrint('✅ Firestore sync success (unlockFish)');
    } catch (e) {
      debugPrint('⚠️ Firestore sync failed (unlockFish): $e');
    }

    notifyListeners();
  }

  // ---------- Neglected ----------
  Future<void> setNeglected(String fishId, bool neglected) async {
    final idx = ownedFishes.indexWhere((f) => f.fishId == fishId);
    if (idx == -1) return;

    ownedFishes[idx] = ownedFishes[idx].copyWith(isNeglected: neglected);

    try {
      final child = _childBox.get(currentChild.cid);
      if (child != null) {
        final updatedFishes = ownedFishes.map((f) => f.toMap()).toList();
        final updatedChild = child.copyWith(ownedFish: updatedFishes);
        await _childBox.put(currentChild.cid, updatedChild);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to persist neglected change to Hive: $e');
    }

    try {
      await _repo.updateOwnedFish(
        currentChild.parentUid,
        currentChild.cid,
        ownedFishes[idx],
      );
    } catch (e) {
      debugPrint('⚠️ updateOwnedFish (neglected) failed: $e');
    }

    notifyListeners();
  }

  // ---------- Edit Mode ----------
  UnmodifiableListView<OwnedFish> get editingFishes =>
      UnmodifiableListView(_editingBuffer);

  void enterEditMode({String? focusFishId}) {
    _editingBuffer = ownedFishes.map((f) => f.copyWith()).toList();
    for (var f in _editingBuffer) f.isSelected = false;

    if (focusFishId != null) {
      final idx = _editingBuffer.indexWhere((f) => f.id == focusFishId);
      if (idx != -1) _editingBuffer[idx].isSelected = true;
    }

    isInEditMode = true;
    movingFishId = null;
    notifyListeners();
  }

  void cancelEditMode() {
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();
  }

  Future<void> saveEditMode() async {
    if (!isInEditMode) return;

    for (var fish in _editingBuffer) {
      try {
        await _repo.updateOwnedFish(
          currentChild.parentUid,
          currentChild.cid,
          fish,
        );
      } catch (e) {
        debugPrint('⚠️ updateOwnedFish in saveEditMode failed: $e');
      }
    }

    ownedFishes = List.from(_editingBuffer);
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();

    if (kDebugMode)
      print("✅ Edit mode saved. ${ownedFishes.length} fishes synced.");
  }

  void toggleFishSelection(String fishId) {
    if (!isInEditMode) enterEditMode(focusFishId: fishId);

    for (var f in _editingBuffer) f.isSelected = false;
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;
    notifyListeners();
  }

  void deselectFish(String fishId) {
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) {
      _editingBuffer[idx].isSelected = false;
      notifyListeners();
    }
  }

  void startMovingFish(String fishId) {
    if (!isInEditMode) return;
    movingFishId = fishId;
    final idx = _editingBuffer.indexWhere((f) => f.id == fishId);
    if (idx != -1) _editingBuffer[idx].isSelected = true;
    notifyListeners();
  }

  void stopMovingFish() {
    movingFishId = null;
    notifyListeners();
  }

  // ---------- Clear ----------
  void clearData() {
    ownedFishes.clear();
    _editingBuffer.clear();
    isInEditMode = false;
    movingFishId = null;
    notifyListeners();
  }

  void refresh() {
    notifyListeners(); // safe internal call
  }
}
