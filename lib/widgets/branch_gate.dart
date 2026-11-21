import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';

/// Wraps [child] in a gate for one notifier type — see [BranchGate.debugGates].
typedef BranchGateBuilder =
    Widget Function<T extends ChangeNotifier>(Widget child);

/// Keeps a tab that is not on screen from rebuilding.
///
/// The shell keeps all its tabs alive (each keeps its scroll position and
/// its pushed pages), so the four that are hidden are still in the tree —
/// and every widget in them that watches the database used to rebuild on
/// every change to it: an import on המאגר שלי, a sync batch, a reminder
/// moving, each rebuilt בית, רעיונות and the rest offstage, on the same
/// thread that draws the page the user is scrolling.
///
/// The gate re-provides the three busy notifiers — the people, the ideas and
/// the card access — to its tab. While the tab is active they pass every
/// change straight through; while it is hidden a change is only noted, and
/// the tab is told once, the moment it becomes visible again (including the
/// first frame of a swipe that reveals it). `context.read` is unaffected:
/// the objects are the same.
class BranchGate extends StatefulWidget {
  const BranchGate({
    super.key,
    required this.active,
    required this.child,
    this.debugGates,
  });

  final bool active;
  final Widget child;

  /// Test seam: gates more notifier types than the three the app gates.
  @visibleForTesting
  final Widget Function(BranchGateBuilder gate, Widget child)? debugGates;

  @override
  State<BranchGate> createState() => _BranchGateState();
}

class _BranchGateState extends State<BranchGate> {
  /// One per provider: tells its dependents, if something changed while the
  /// tab was hidden.
  final List<VoidCallback> _catchUp = <VoidCallback>[];

  bool get _active => widget.active;

  @override
  void didUpdateWidget(covariant BranchGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      for (final VoidCallback catchUp in List<VoidCallback>.of(_catchUp)) {
        catchUp();
      }
    }
  }

  Widget _gate<T extends ChangeNotifier>(Widget child) {
    final T? value;
    try {
      value = Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return child;
    }
    return InheritedProvider<T>.value(
      value: value,
      startListening: (InheritedContext<T?> element, T notifier) {
        bool missed = false;
        void onChange() {
          if (_active) {
            element.markNeedsNotifyDependents();
          } else {
            missed = true;
          }
        }

        void catchUp() {
          if (!missed) return;
          missed = false;
          element.markNeedsNotifyDependents();
        }

        notifier.addListener(onChange);
        _catchUp.add(catchUp);
        return () {
          notifier.removeListener(onChange);
          _catchUp.remove(catchUp);
        };
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = widget.debugGates == null
        ? widget.child
        : widget.debugGates!(_gate, widget.child);
    return _gate<PersonRepository>(
      _gate<MatchRepository>(_gate<CardAccessProvider>(child)),
    );
  }
}
