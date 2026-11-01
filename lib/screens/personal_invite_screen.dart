import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/workspace_store.dart';

class PersonalInviteScreen extends StatefulWidget {
  const PersonalInviteScreen({super.key});
  @override
  State<PersonalInviteScreen> createState() => _PersonalInviteScreenState();
}

class _PersonalInviteScreenState extends State<PersonalInviteScreen> {
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _redeem();
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = InviteLinkService.pending?.personalToken;
    if (token == null) {
      setState(() {
        _error = 'ההזמנה אינה זמינה';
        _busy = false;
      });
      return;
    }
    try {
      final result = await PersonalAreaService.call('redeemPersonalInvite', {
        'token': token,
        'name': context.read<UserProfileProvider>().fullName ?? '',
      });
      if (!mounted) return;
      InviteLinkService.clear();
      WorkspaceStore.setMatchmakerEnabled(true);
      WorkspaceStore.setLastArea(WorkArea.matchmaker);
      await context.read<CardAccessProvider>().ensureConnected();
      if (mounted) context.go('/card-friend/${result['ownerUid']}');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'ההזמנה אינה זמינה';
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'לא הצלחנו לפתוח את ההזמנה. כדאי לבדוק את החיבור.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('הזמנה אישית לשדכן')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _busy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error ?? ''),
                  const SizedBox(height: 8),
                  const Text(
                    'אם צריך להחליף חשבון, יש להתחבר עם האימייל שאליו נשלחה ההזמנה ולפתוח שוב את הקישור.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _redeem,
                    child: const Text('ניסיון נוסף'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/profile/account'),
                    child: const Text('החלפת חשבון'),
                  ),
                  TextButton(
                    onPressed: () {
                      InviteLinkService.clear();
                      context.go(
                        WorkspaceStore.matchmakerEnabled ? '/home' : '/me',
                      );
                    },
                    child: const Text('לא עכשיו'),
                  ),
                ],
              ),
      ),
    ),
  );
}
