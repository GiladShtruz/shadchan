import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/date_utils.dart';

/// Status time is separate from ordinary card edits and never a journal row.
class CardStatusTimestamp extends StatelessWidget {
  const CardStatusTimestamp({super.key, required this.ownerUid});
  final String? ownerUid;
  @override
  Widget build(BuildContext context) {
    if (ownerUid == null || !FirebaseBootstrap.isReady) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('personalCards/$ownerUid')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final time = snapshot.data?.data()?['statusUpdatedAt'];
        if (time is! Timestamp) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            'עודכן לאחרונה ${AppDateUtils.timeAgoShort(time.toDate())}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        );
      },
    );
  }
}
