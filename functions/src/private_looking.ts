import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

/** Decode the actual uploaded media on the server, never trust client duration. */
export const savePrivateLooking = onCall(
  { region: 'europe-west1', timeoutSeconds: 120, memory: '512MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth?.token.firebase?.sign_in_provider === 'anonymous')
      throw new HttpsError('unauthenticated', 'נדרשת התחברות');
    const text = request.data?.text;
    let audioPath = request.data?.audioPath;
    const uploadedPath = audioPath;
    if (
      typeof text !== 'string' ||
      text.length > 12000 ||
      (audioPath !== null &&
        (typeof audioPath !== 'string' ||
          !audioPath.startsWith(`privateLooking/${uid}/`) ||
          audioPath.split('/').length !== 3))
    ) {
      throw new HttpsError('invalid-argument', 'תוכן לא תקין');
    }
    const db = getFirestore();
    const ref = db.doc(`privateLooking/${uid}`);
    const previous = await ref.get();
    let durationMs: number | null = null;
    if (audioPath) {
      if (
        audioPath === previous.get('audioPath') &&
        previous.get('durationMs')
      ) {
        durationMs = previous.get('durationMs');
      } else {
        const file = getStorage().bucket().file(audioPath);
        const [metadata] = await file.getMetadata();
        if (Number(metadata.size) > 30 * 1024 * 1024)
          throw new HttpsError('invalid-argument', 'הקלטה גדולה מדי');
        const folder = await mkdtemp(join(tmpdir(), 'looking-'));
        try {
          const local = join(folder, 'audio');
          await file.download({ destination: local });
          // ffprobe-static is packaged with the function; no shell or user arguments.
          const { path } = require('ffprobe-static') as { path: string };
          const { stdout } = await promisify(execFile)(
            path,
            [
              '-v',
              'error',
              '-show_format',
              '-show_streams',
              '-of',
              'json',
              local,
            ],
            { timeout: 30000, maxBuffer: 1024 * 1024 },
          );
          const probe = JSON.parse(stdout);
          durationMs = Math.round(Number(probe.format?.duration) * 1000);
          if (
            !Number.isFinite(durationMs) ||
            durationMs! <= 0 ||
            durationMs! > 600000 ||
            !probe.streams?.some(
              (s: { codec_type: string }) => s.codec_type === 'audio',
            ) ||
            probe.streams?.some(
              (s: { codec_type: string }) => s.codec_type === 'video',
            )
          ) {
            throw new HttpsError(
              'invalid-argument',
              'אפשר לצרף הקלטת קול עד 10 דקות בלבד',
            );
          }
          // WhatsApp's Opus/Ogg and AMR containers are not playable by every iOS
          // version. Store one AAC file so the same recording plays on both platforms.
          if (/\.(opus|ogg|oga|amr|3gp)$/i.test(audioPath)) {
            const output = join(folder, 'recording.m4a');
            const ffmpeg = (
              require('@ffmpeg-installer/ffmpeg') as { path: string }
            ).path;
            await promisify(execFile)(
              ffmpeg,
              [
                '-nostdin',
                '-v',
                'error',
                '-i',
                local,
                '-vn',
                '-ac',
                '1',
                '-c:a',
                'aac',
                '-b:a',
                '64k',
                '-movflags',
                '+faststart',
                output,
              ],
              { timeout: 60000, maxBuffer: 1024 * 1024 },
            );
            audioPath = `privateLooking/${uid}/converted_${randomUUID()}.m4a`;
            await getStorage()
              .bucket()
              .upload(output, {
                destination: audioPath,
                metadata: { contentType: 'audio/mp4' },
              });
          }
        } finally {
          await rm(folder, { recursive: true, force: true });
        }
      }
    }
    if (audioPath) {
      // Keep revocation tied to authenticated Storage rules, never a permanent bearer URL.
      await getStorage()
        .bucket()
        .file(audioPath)
        .setMetadata({ metadata: { firebaseStorageDownloadTokens: null } });
    }
    const batch = db.batch();
    batch.set(ref, {
      ownerUid: uid,
      text: text.trim(),
      audioPath,
      durationMs,
      everFilled:
        previous.get('everFilled') === true || !!text.trim() || !!audioPath,
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(db.doc(`privateLookingPresence/${uid}`), {
      hasContent: !!text.trim() || !!audioPath,
    });
    await batch.commit();
    if (uploadedPath && uploadedPath !== audioPath)
      await getStorage()
        .bucket()
        .file(uploadedPath)
        .delete({ ignoreNotFound: true });
    const old = previous.get('audioPath');
    if (old && old !== audioPath)
      await getStorage().bucket().file(old).delete({ ignoreNotFound: true });
    return { saved: true };
  },
);
