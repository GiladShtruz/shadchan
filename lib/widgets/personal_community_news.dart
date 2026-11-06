import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/home_section.dart';

class PersonalCommunityNews extends StatefulWidget {
  const PersonalCommunityNews({super.key, this.includeStats = true});

  /// False where the community's figures are already said on their own line
  /// (the personal home's [PersonalCommunityLine]) — then only the
  /// administrator's published news turn over here.
  final bool includeStats;
  @override
  State<PersonalCommunityNews> createState() => _PersonalCommunityNewsState();
}

class _PersonalCommunityNewsState extends State<PersonalCommunityNews>
    with WidgetsBindingObserver {
  bool _paused = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  void _step(int delta, int length) {
    setState(() {
      _paused = true; // Reading manually must not be interrupted by the timer.
      _index = (_index + delta) % length;
    });
  }

  Timer? _timer;
  int _index = 0;
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<PersonalAreaProvider>();
    final stats = data.stats;
    final items = <PersonalNews>[...data.news];
    if (widget.includeStats && stats['weekKey'] == CommunityPeriods.weekKey()) {
      for (final entry in <(String, String)>[
        ('newSinglesWeek', 'רווקים ורווקות הצטרפו השבוע'),
        ('newMatchmakersWeek', 'שדכנים חדשים הצטרפו השבוע'),
        ('activeMatchmakers', 'שדכנים פעילים בקהילה השבוע'),
        ('couplesWeek', 'זוגות התחילו לצאת השבוע'),
        ('engagementsWeek', 'אירוסים דווחו השבוע'),
      ]) {
        final value = stats[entry.$1];
        if (value is num && value > 0) {
          items.add(
            PersonalNews(
              id: entry.$1,
              title: 'הקהילה ממשיכה להתחבר ❤️',
              text: '$value ${entry.$2}',
            ),
          );
        }
      }
    }
    final animate =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (items.length > 1 && animate && !_paused && _foreground) {
      _timer ??= Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted) setState(() => _index++);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[_index % items.length];
    final card = HomePaperCard(
      stripe: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'מה חדש בקהילת שדכן?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: Duration(milliseconds: animate ? 350 : 0),
            child: Column(
              key: ValueKey(item.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.imagePath != null)
                  PersonalNewsImage(
                    key: ValueKey(item.imagePath),
                    path: item.imagePath!,
                  ),
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(item.text, maxLines: 5, overflow: TextOverflow.ellipsis),
                if (data.news.any((n) => n.id == item.id))
                  TextButton(
                    onPressed: () => context.push('/me/news/${item.id}'),
                    child: const Text('לקריאת העדכון'),
                  ),
              ],
            ),
          ),
          if (items.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'העדכון הקודם',
                  onPressed: () => _step(-1, items.length),
                  icon: const Icon(Icons.chevron_right),
                ),
                if (animate)
                  IconButton(
                    tooltip: _paused
                        ? 'המשך מעבר אוטומטי'
                        : 'השהיית המעבר האוטומטי',
                    onPressed: () => setState(() => _paused = !_paused),
                    icon: Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                  ),
                Text(
                  '${_index % items.length + 1} / ${items.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'העדכון הבא',
                  onPressed: () => _step(1, items.length),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
        ],
      ),
    );
    return widget.includeStats
        ? card
        : Padding(padding: const EdgeInsets.only(top: 12), child: card);
  }
}

class PersonalNewsImage extends StatefulWidget {
  const PersonalNewsImage({super.key, required this.path});
  final String path;
  @override
  State<PersonalNewsImage> createState() => _PersonalNewsImageState();
}

class _PersonalNewsImageState extends State<PersonalNewsImage> {
  late final _bytes = FirebaseStorage.instance
      .ref(widget.path)
      .getData(12 * 1024 * 1024);
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _bytes,
    builder: (_, snap) => snap.hasData
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(snap.data!, height: 180, fit: BoxFit.contain),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class PersonalNewsDetailScreen extends StatelessWidget {
  const PersonalNewsDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('מה חדש בקהילת שדכן')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseBootstrap.isReady
          ? FirebaseFirestore.instance.doc('personalNews/$id').snapshots()
          : null,
      builder: (context, snapshot) {
        if (snapshot.hasError || snapshot.data?.exists == false) {
          return const Center(child: Text('העדכון כבר אינו זמין'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final news = PersonalNews.fromMap(id, snapshot.data!.data()!);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (news.imagePath != null)
              PersonalNewsImage(
                key: ValueKey(news.imagePath),
                path: news.imagePath!,
              ),
            Text(news.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(news.text),
          ],
        );
      },
    ),
  );
}
