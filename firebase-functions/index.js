const crypto = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");

initializeApp();

const db = getFirestore();
const serverTimestamp = FieldValue.serverTimestamp;
const GROUP_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CODE_PATTERN = /^\d{6}$/;
const PROFILE_COLORS = new Set(["orange", "blue", "green", "red", "purple", "pink"]);
const PROFILE_ICONS = new Set([
  "tortoise.fill", "hare.fill", "pawprint.fill", "bird.fill", "ladybug.fill", "ant.fill",
  "motorcycle", "map.fill", "location.fill", "flag.checkered", "fuelpump.fill", "helmet",
]);

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です。");
  }
  return request.auth.uid;
}

function requiredString(value, field, maxLength) {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field}が正しくありません。`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field}の長さが正しくありません。`);
  }
  return trimmed;
}

function optionalString(value, field, maxLength) {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  if (typeof value !== "string" || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field}が正しくありません。`);
  }
  return value;
}

function requireGroupID(value) {
  const groupID = requiredString(value, "groupID", 36);
  if (!GROUP_ID_PATTERN.test(groupID)) {
    throw new HttpsError("invalid-argument", "groupIDが正しくありません。");
  }
  return groupID.toUpperCase();
}

function memberData(data, uid) {
  const profileColorRawValue = requiredString(data.profileColorRawValue, "プロフィール色", 64);
  const profileIconRawValue = requiredString(data.profileIconRawValue, "プロフィールアイコン", 80);
  if (!PROFILE_COLORS.has(profileColorRawValue) || !PROFILE_ICONS.has(profileIconRawValue)) {
    throw new HttpsError("invalid-argument", "プロフィール設定が正しくありません。");
  }

  const result = {
    displayName: requiredString(data.displayName, "表示名", 40),
    profileColorRawValue,
    profileIconRawValue,
    deviceID: optionalString(data.deviceID, "deviceID", 100),
    authUID: uid,
    updatedAt: serverTimestamp(),
  };

  const fcmToken = optionalString(data.fcmToken, "FCMトークン", 4096);
  if (fcmToken) {
    result.fcmToken = fcmToken;
  }
  return result;
}

async function requireMember(groupID, uid) {
  const memberRef = db.doc(`groups/${groupID}/members/${uid}`);
  const memberSnapshot = await memberRef.get();
  if (!memberSnapshot.exists) {
    throw new HttpsError("permission-denied", "このグループのメンバーではありません。");
  }
  return memberSnapshot;
}

async function recordJoinAttempt(uid) {
  const ref = db.doc(`joinRateLimits/${uid}`);
  const now = Date.now();

  const status = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() || {};
    const windowStart = data.windowStart?.toMillis?.() || 0;
    const blockedUntil = data.blockedUntil?.toMillis?.() || 0;

    if (blockedUntil > now) {
      return "blocked";
    }

    const isCurrentWindow = now - windowStart < 60_000;
    const attemptCount = isCurrentWindow ? (data.attemptCount || 0) + 1 : 1;
    const nextData = {
      attemptCount,
      windowStart: Timestamp.fromMillis(isCurrentWindow ? windowStart : now),
      updatedAt: serverTimestamp(),
    };

    if (attemptCount > 8) {
      nextData.blockedUntil = Timestamp.fromMillis(now + 5 * 60_000);
      transaction.set(ref, nextData, { merge: true });
      return "newly-blocked";
    }

    transaction.set(ref, nextData, { merge: true });
    return "allowed";
  });

  if (status !== "allowed") {
    throw new HttpsError("resource-exhausted", "参加操作が多すぎます。5分後に再試行してください。");
  }
}

exports.createGroup = onCall(async (request) => {
  const uid = requireAuth(request);
  const name = requiredString(request.data?.name, "グループ名", 60);
  const groupID = crypto.randomUUID().toUpperCase();
  const groupRef = db.doc(`groups/${groupID}`);
  const memberRef = groupRef.collection("members").doc(uid);
  const profile = memberData(request.data || {}, uid);

  for (let attempt = 0; attempt < 20; attempt += 1) {
    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
    const codeRef = db.doc(`groupCodes/${code}`);

    try {
      await db.runTransaction(async (transaction) => {
        const codeSnapshot = await transaction.get(codeRef);
        if (codeSnapshot.exists) {
          throw new Error("CODE_COLLISION");
        }

        transaction.create(codeRef, { groupID, createdAt: serverTimestamp() });
        transaction.create(groupRef, {
          name,
          code,
          ownerAuthUID: uid,
          ownerDeviceID: profile.deviceID,
          memberCount: 1,
          arrivedCount: 0,
          lastMessageText: "",
          createdAt: serverTimestamp(),
        });
        transaction.create(memberRef, {
          ...profile,
          isArrived: false,
          joinedAt: serverTimestamp(),
        });
      });
      return { groupID, code, name };
    } catch (error) {
      if (error.message !== "CODE_COLLISION") {
        console.error("createGroup failed");
        throw new HttpsError("internal", "グループを作成できませんでした。");
      }
    }
  }

  throw new HttpsError("resource-exhausted", "参加コードを発行できませんでした。もう一度お試しください。");
});

exports.joinGroup = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = requiredString(request.data?.code, "参加コード", 6);
  if (!CODE_PATTERN.test(code)) {
    throw new HttpsError("invalid-argument", "参加コードは6桁の数字で入力してください。");
  }

  await recordJoinAttempt(uid);

  let groupID;
  const codeRef = db.doc(`groupCodes/${code}`);
  const codeSnapshot = await codeRef.get();
  if (codeSnapshot.exists) {
    groupID = codeSnapshot.get("groupID");
  } else {
    const legacySnapshot = await db.collection("groups")
      .where("code", "==", code)
      .limit(1)
      .get();
    if (legacySnapshot.empty) {
      throw new HttpsError("not-found", "その参加コードのグループは存在しません。");
    }
    groupID = legacySnapshot.docs[0].id;
  }

  if (typeof groupID !== "string" || !GROUP_ID_PATTERN.test(groupID)) {
    throw new HttpsError("not-found", "グループ情報が正しくありません。");
  }

  const groupRef = db.doc(`groups/${groupID}`);
  const memberRef = groupRef.collection("members").doc(uid);
  const profile = memberData(request.data || {}, uid);

  const groupData = await db.runTransaction(async (transaction) => {
    const groupSnapshot = await transaction.get(groupRef);
    const memberSnapshot = await transaction.get(memberRef);
    if (!groupSnapshot.exists) {
      throw new HttpsError("not-found", "グループが削除されています。");
    }

    transaction.set(memberRef, {
      ...profile,
      isArrived: memberSnapshot.exists ? memberSnapshot.get("isArrived") === true : false,
      joinedAt: memberSnapshot.exists ? (memberSnapshot.get("joinedAt") || serverTimestamp()) : serverTimestamp(),
    }, { merge: true });

    if (!memberSnapshot.exists) {
      transaction.update(groupRef, {
        memberCount: FieldValue.increment(1),
        updatedAt: serverTimestamp(),
      });
    }
    return groupSnapshot.data();
  });

  await codeRef.set({ groupID, createdAt: serverTimestamp() }, { merge: true });
  return {
    groupID,
    name: groupData.name || "ツーリンググループ",
    code,
    ownerAuthUID: groupData.ownerAuthUID || "",
  };
});

exports.migrateLegacyMembership = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  const deviceID = requiredString(request.data?.deviceID, "deviceID", 100);
  const groupRef = db.doc(`groups/${groupID}`);
  const newMemberRef = groupRef.collection("members").doc(uid);
  const legacyMemberRef = groupRef.collection("members").doc(deviceID);

  return db.runTransaction(async (transaction) => {
    const groupSnapshot = await transaction.get(groupRef);
    const newSnapshot = await transaction.get(newMemberRef);
    const legacySnapshot = await transaction.get(legacyMemberRef);

    if (!groupSnapshot.exists) {
      return { authorized: false, reason: "not-found" };
    }
    if (newSnapshot.exists) {
      return { authorized: true, migrated: false };
    }

    const legacyData = legacySnapshot.data();
    const isLegacyMember = legacySnapshot.exists && legacyData.authUID === uid;
    const isOwner = groupSnapshot.get("ownerAuthUID") === uid;
    if (!isLegacyMember && !isOwner) {
      return { authorized: false, reason: "not-member" };
    }

    const source = legacyData || {};
    transaction.set(newMemberRef, {
      displayName: requiredString(source.displayName || "メンバー", "表示名", 40),
      profileColorRawValue: optionalString(source.profileColorRawValue, "プロフィール色", 64) || "orange",
      profileIconRawValue: optionalString(source.profileIconRawValue, "プロフィールアイコン", 80) || "person.crop.circle.fill",
      deviceID,
      authUID: uid,
      fcmToken: optionalString(source.fcmToken, "FCMトークン", 4096),
      isArrived: source.isArrived === true,
      joinedAt: source.joinedAt || serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, { merge: true });

    if (legacySnapshot.exists && legacyMemberRef.path !== newMemberRef.path) {
      transaction.delete(legacyMemberRef);
    }
    return { authorized: true, migrated: true };
  });
});

exports.updateMemberProfile = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  await requireMember(groupID, uid);
  await db.doc(`groups/${groupID}/members/${uid}`).set(memberData(request.data || {}, uid), { merge: true });
  return { success: true };
});

exports.sendGroupMessage = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  const text = requiredString(request.data?.text, "メッセージ", 1000);
  const memberSnapshot = await requireMember(groupID, uid);
  const messageRef = db.collection(`groups/${groupID}/messages`).doc();

  await messageRef.create({
    text,
    senderName: memberSnapshot.get("displayName") || "メンバー",
    senderDeviceID: memberSnapshot.get("deviceID") || "",
    senderAuthUID: uid,
    sentAt: serverTimestamp(),
  });
  return { messageID: messageRef.id };
});

exports.leaveGroup = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  const groupRef = db.doc(`groups/${groupID}`);
  const memberRef = groupRef.collection("members").doc(uid);

  await db.runTransaction(async (transaction) => {
    const groupSnapshot = await transaction.get(groupRef);
    const memberSnapshot = await transaction.get(memberRef);
    if (!groupSnapshot.exists || !memberSnapshot.exists) {
      return;
    }
    if (groupSnapshot.get("ownerAuthUID") === uid) {
      throw new HttpsError("failed-precondition", "オーナーはグループを退出できません。削除を選んでください。");
    }

    transaction.delete(memberRef);
    transaction.update(groupRef, {
      memberCount: FieldValue.increment(-1),
      arrivedCount: FieldValue.increment(memberSnapshot.get("isArrived") === true ? -1 : 0),
      updatedAt: serverTimestamp(),
    });
  });
  return { success: true };
});

exports.updateArrivalStatus = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  if (typeof request.data?.isArrived !== "boolean") {
    throw new HttpsError("invalid-argument", "到着状態が正しくありません。");
  }

  const groupRef = db.doc(`groups/${groupID}`);
  const memberRef = groupRef.collection("members").doc(uid);
  await db.runTransaction(async (transaction) => {
    const memberSnapshot = await transaction.get(memberRef);
    if (!memberSnapshot.exists) {
      throw new HttpsError("permission-denied", "このグループのメンバーではありません。");
    }
    const wasArrived = memberSnapshot.get("isArrived") === true;
    const nextArrived = request.data.isArrived;
    if (wasArrived === nextArrived) {
      return;
    }

    transaction.update(memberRef, { isArrived: nextArrived, updatedAt: serverTimestamp() });
    transaction.update(groupRef, {
      arrivedCount: FieldValue.increment(nextArrived ? 1 : -1),
      updatedAt: serverTimestamp(),
    });
  });
  return { success: true };
});

exports.deleteGroup = onCall(async (request) => {
  const uid = requireAuth(request);
  const groupID = requireGroupID(request.data?.groupID);
  const groupRef = db.doc(`groups/${groupID}`);
  const groupSnapshot = await groupRef.get();
  if (!groupSnapshot.exists) {
    return { success: true };
  }
  if (groupSnapshot.get("ownerAuthUID") !== uid) {
    throw new HttpsError("permission-denied", "グループを削除できるのはオーナーだけです。");
  }

  const code = groupSnapshot.get("code");
  await db.recursiveDelete(groupRef);
  if (typeof code === "string" && CODE_PATTERN.test(code)) {
    await db.doc(`groupCodes/${code}`).delete().catch(() => undefined);
  }
  return { success: true };
});

exports.syncGroupLastMessage = onDocumentWritten(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const groupRef = db.doc(`groups/${event.params.groupId}`);
    const latest = await groupRef.collection("messages").orderBy("sentAt", "desc").limit(1).get();

    if (latest.empty) {
      await groupRef.update({
        lastMessageText: "",
        lastMessageAt: FieldValue.delete(),
      }).catch((error) => {
        if (error.code !== 5) throw error;
      });
      return;
    }

    const message = latest.docs[0].data();
    await groupRef.update({
      lastMessageText: typeof message.text === "string" ? message.text : "",
      lastMessageAt: message.sentAt || serverTimestamp(),
    }).catch((error) => {
      if (error.code !== 5) throw error;
    });
  }
);

exports.notifyGroupMessage = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message || typeof message.senderAuthUID !== "string") {
      return;
    }

    const groupId = event.params.groupId;
    const groupRef = db.doc(`groups/${groupId}`);
    const [groupSnapshot, senderSnapshot, membersSnapshot] = await Promise.all([
      groupRef.get(),
      groupRef.collection("members").doc(message.senderAuthUID).get(),
      groupRef.collection("members").get(),
    ]);

    if (!groupSnapshot.exists || !senderSnapshot.exists) {
      console.warn("Rejected notification for a non-member message", {
        groupId,
        messageId: event.params.messageId,
      });
      return;
    }

    const tokens = [];
    membersSnapshot.forEach((doc) => {
      const member = doc.data();
      if (doc.id !== message.senderAuthUID && typeof member.fcmToken === "string") {
        tokens.push(member.fcmToken);
      }
    });
    const uniqueTokens = [...new Set(tokens)];
    if (uniqueTokens.length === 0) {
      return;
    }

    const response = await getMessaging().sendEachForMulticast({
      tokens: uniqueTokens,
      notification: {
        title: groupSnapshot.get("name") || "ツーリングチャット",
        body: "新しいメッセージが届きました",
      },
      data: { groupId, messageId: event.params.messageId },
      apns: { payload: { aps: { sound: "default" } } },
    });

    const invalidCodes = new Set([
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
    ]);
    const cleanup = [];
    response.responses.forEach((item, index) => {
      if (!item.success && invalidCodes.has(item.error?.code)) {
        const invalidToken = uniqueTokens[index];
        membersSnapshot.forEach((doc) => {
          if (doc.get("fcmToken") === invalidToken) {
            cleanup.push(doc.ref.update({
              fcmToken: FieldValue.delete(),
              updatedAt: serverTimestamp(),
            }));
          }
        });
      }
    });
    await Promise.all(cleanup);
  }
);
