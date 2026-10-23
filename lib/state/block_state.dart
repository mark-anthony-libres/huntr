import 'package:flutter/widgets.dart';

import '../services/block_service.dart';
import '../services/huntr_backend.dart';

/// What the app knows of blocks between me and others, kept up to date: each
/// person's status is checked again whenever their profile or chat opens,
/// when the backend says a block changed (either side), and after the live
/// connection comes back. The backend enforces blocks; this only decides
/// what the screens show.
class BlockState extends ChangeNotifier {
  BlockState({required this.service, required this.token});

  final BlockService service;
  final String? Function() token;

  final Map<int, BlockStatus> _status = {};

  /// The status last checked (null: not checked yet).
  BlockStatus? statusOf(int userId) => _status[userId];

  /// Checks again with the backend (its answer is what counts).
  Future<BlockStatus?> check(int userId) async {
    final current = token();
    if (current == null) return null;
    try {
      final status = await service.status(current, userId);
      _set(userId, status);
      return status;
    } catch (error) {
      debugPrint('Block status not checked: $error');
      return _status[userId];
    }
  }

  /// Everyone checked before, again (e.g. after reconnecting).
  Future<void> checkAll() async {
    for (final userId in [..._status.keys]) {
      await check(userId);
    }
  }

  /// I block them. Throws what the backend says.
  Future<void> block(int userId) async {
    final current = token();
    if (current == null) return;
    await service.block(current, userId);
    await check(userId);
  }

  /// I lift my block (the backend refuses it before its date). Throws what
  /// the backend says.
  Future<void> unblock(int userId) async {
    final current = token();
    if (current == null) return;
    await service.unblock(current, userId);
    await check(userId);
  }

  /// I lift my block of someone I only know anonymously (by conversation).
  Future<void> unblockAnonymous(int conversationId) async {
    final current = token();
    if (current == null) return;
    await service.unblockAnonymous(current, conversationId);
  }

  Future<List<BlockedPerson>> mine() async {
    final current = token();
    if (current == null) return const [];
    return service.mine(current);
  }

  /// Known from elsewhere (the chat list carries it).
  void learn(int userId, BlockStatus status) => _set(userId, status);

  void clear() {
    _status.clear();
    notifyListeners();
  }

  void _set(int userId, BlockStatus status) {
    final before = _status[userId];
    _status[userId] = status;
    if (before == null ||
        before.blockedByMe != status.blockedByMe ||
        before.blockedMe != status.blockedMe ||
        before.canUnblock != status.canUnblock) {
      notifyListeners();
    }
  }
}

/// Gives [BlockState] to the screens below (null: no blocking, e.g. tests
/// and sample data).
class BlockScope extends InheritedNotifier<BlockState> {
  const BlockScope(
      {super.key, required BlockState? state, required super.child})
      : super(notifier: state);

  static BlockState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlockScope>()?.notifier;

  static BlockState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BlockScope>()?.notifier;
}
