/// Changes that arrive by **sync** — the account's own records coming down
/// after a reconnect, a friend's personal card following itself into the
/// database — are not something the matchmaker just did. They are drawn
/// (the list updates) and they count where they always counted, but nothing
/// celebrates them: no "+1", no milestone toast, no "חבר חדש נוסף".
///
/// A repository notifies its listeners inside [run]; a listener that rewards
/// work asks [active] and stays quiet for that change.
abstract final class SyncQuiet {
  static int _depth = 0;

  /// Whether the change being reported right now came from a sync.
  static bool get active => _depth > 0;

  static void run(void Function() notify) {
    _depth++;
    try {
      notify();
    } finally {
      _depth--;
    }
  }
}
