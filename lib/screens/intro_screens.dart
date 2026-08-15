import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// One page of the welcome.
class IntroPage {
  const IntroPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// The first thing a new matchmaker sees: four short cards, one thought each.
///
/// Not a tutorial. Nothing here explains a button, because a tour of an app
/// nobody has used yet is forgotten before the first tap. What it does say is
/// the one thing that cannot be discovered by using the app and that changes
/// how freely someone uses it: **this database is private, and nobody else can
/// see it.** A matchmaker who is not sure of that hesitates before adding a
/// friend who never asked to be added — which is most of the database.
///
/// Shown once, before the profile form, and never again.
class IntroScreens extends StatefulWidget {
  const IntroScreens({super.key, required this.onFinished});

  /// Called when the last page is accepted, or the welcome is skipped.
  final VoidCallback onFinished;

  static const List<IntroPage> pages = <IntroPage>[
    IntroPage(
      icon: Icons.favorite_rounded,
      title: 'האפליקציה הזו נבנתה בשבילך',
      body:
          'לשדכנים, ולכל מי שחושב מדי פעם על החברים שלו ומחפש להם את '
          'ההתאמה הנכונה.',
    ),
    IntroPage(
      icon: Icons.folder_shared_outlined,
      title: 'מאגר השידוכים האישי שלך',
      body:
          'החברים שאתם חושבים עליהם, הרעיונות שעולים לכם בראש ומה קרה עם כל '
          'אחד מהם — הכול נשמר במקום אחד, אצלכם.',
    ),
    IntroPage(
      icon: Icons.lock_outline_rounded,
      title: 'פרטי לחלוטין',
      body:
          'אף משתמש אחר לא יכול לראות את המאגר שלכם, את הרעיונות שלכם או את '
          'הפעילות שלכם. גם לא שדכנים אחרים.',
    ),
    IntroPage(
      icon: Icons.group_add_outlined,
      title: 'אפשר להוסיף בלב שקט',
      body:
          'אפשר להוסיף למאגר חברים שאתם חושבים עליהם לשידוכים גם בלי לבקש '
          'מהם מראש לפתוח פרופיל. כל מה שתוסיפו נשאר במאגר האישי שלכם בלבד.',
    ),
  ];

  @override
  State<IntroScreens> createState() => _IntroScreensState();
}

class _IntroScreensState extends State<IntroScreens> {
  final PageController _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == IntroScreens.pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                // Never a trap: someone who wants to get on with it can.
                onPressed: widget.onFinished,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('דילוג'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: IntroScreens.pages.length,
                onPageChanged: (int page) => setState(() => _page = page),
                itemBuilder: (BuildContext context, int index) {
                  return _IntroPageView(
                    page: IntroScreens.pages[index],
                    lead: lead,
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < IntroScreens.pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: lead.withValues(alpha: i == _page ? 0.9 : 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: lead,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                    textStyle: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(_isLast ? 'מתחילים' : 'המשך'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page, required this.lead});

  final IntroPage page;
  final Color lead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const SizedBox(height: 24),
          Container(
            width: 108,
            height: 108,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lead.withValues(alpha: 0.10),
            ),
            child: Icon(page.icon, size: 52, color: lead),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
