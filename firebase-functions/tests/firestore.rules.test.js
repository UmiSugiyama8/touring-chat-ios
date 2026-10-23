const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  deleteField,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  increment,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const projectId = "demo-touring-app";
const groupId = "11111111-1111-4111-8111-111111111111";
const code = "123456";
let testEnvironment;

function memberData(uid, name, deviceID, joinCode) {
  const data = {
    displayName: name,
    profileColorRawValue: "orange",
    profileIconRawValue: "tortoise.fill",
    deviceID,
    authUID: uid,
    isArrived: false,
    joinedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
  if (joinCode) data.joinCode = joinCode;
  return data;
}

async function createGroupAsOwner(db) {
  const batch = writeBatch(db);
  batch.set(doc(db, `groups/${groupId}`), {
    name: "テストグループ",
    code,
    ownerAuthUID: "owner-uid",
    ownerDeviceID: "owner-device",
    memberCount: 1,
    arrivedCount: 0,
    lastMessageText: "",
    createdAt: serverTimestamp(),
  });
  batch.set(
    doc(db, `groups/${groupId}/members/owner-uid`),
    memberData("owner-uid", "オーナー", "owner-device")
  );
  batch.set(doc(db, `groupCodes/${code}`), {
    groupID: groupId,
    ownerAuthUID: "owner-uid",
    createdAt: serverTimestamp(),
  });
  await batch.commit();
}

async function joinMember(db, uid = "member-uid") {
  const batch = writeBatch(db);
  batch.set(doc(db, `groups/${groupId}/members/${uid}`),
    memberData(uid, "メンバー", `${uid}-device`, code));
  batch.update(doc(db, `groups/${groupId}`), {
    memberCount: increment(1), updatedAt: serverTimestamp(),
  });
  await batch.commit();
}

test.before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
});

test.after(async () => {
  await testEnvironment?.cleanup();
});

test.beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

test("Spark-plan Firestore rules protect group data", async (t) => {
  const ownerDB = testEnvironment.authenticatedContext("owner-uid").firestore();
  const memberDB = testEnvironment.authenticatedContext("member-uid").firestore();
  const outsiderDB = testEnvironment.authenticatedContext("outsider-uid").firestore();

  await t.test("an authenticated user can atomically create a valid group", async () => {
    await assertSucceeds(createGroupAsOwner(ownerDB));
    await assertSucceeds(getDoc(doc(ownerDB, `groups/${groupId}`)));
  });

  await t.test("an outsider can resolve an exact invite code but cannot read the group", async () => {
    await createGroupAsOwner(ownerDB);
    await assertSucceeds(getDoc(doc(outsiderDB, `groupCodes/${code}`)));
    await assertFails(getDocs(collection(outsiderDB, "groupCodes")));
    await assertFails(getDoc(doc(outsiderDB, `groups/${groupId}`)));
  });

  await t.test("a user can join with the correct code and then read only that group", async () => {
    await createGroupAsOwner(ownerDB);
    const batch = writeBatch(memberDB);
    batch.set(
      doc(memberDB, `groups/${groupId}/members/member-uid`),
      memberData("member-uid", "メンバー", "member-device", code)
    );
    batch.update(doc(memberDB, `groups/${groupId}`), {
      memberCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDoc(doc(memberDB, `groups/${groupId}`)));
    await assertSucceeds(getDocs(query(
      collection(memberDB, "groups"),
      where(documentId(), "in", [groupId])
    )));
  });

  await t.test("joining without the correct code is rejected", async () => {
    await createGroupAsOwner(ownerDB);
    const batch = writeBatch(outsiderDB);
    batch.set(
      doc(outsiderDB, `groups/${groupId}/members/outsider-uid`),
      memberData("outsider-uid", "部外者", "outsider-device", "999999")
    );
    batch.update(doc(outsiderDB, `groups/${groupId}`), {
      memberCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  await t.test("a member can post only with the verified profile", async () => {
    await createGroupAsOwner(ownerDB);
    const messageId = "22222222-2222-4222-8222-222222222222";
    const validBatch = writeBatch(ownerDB);
    validBatch.set(doc(ownerDB, `groups/${groupId}/messages/${messageId}`), {
      text: "出発する",
      senderName: "オーナー",
      senderDeviceID: "owner-device",
      senderAuthUID: "owner-uid",
      sentAt: serverTimestamp(),
    });
    validBatch.update(doc(ownerDB, `groups/${groupId}`), {
      lastMessageText: "出発する",
      lastMessageAt: serverTimestamp(),
      lastMessageID: messageId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(validBatch.commit());

    await assertFails(setDoc(
      doc(ownerDB, `groups/${groupId}/messages/spoofed`),
      {
        text: "なりすまし",
        senderName: "別人",
        senderDeviceID: "owner-device",
        senderAuthUID: "owner-uid",
        sentAt: serverTimestamp(),
      }
    ));
  });

  await t.test("only the owner can change group settings", async () => {
    await createGroupAsOwner(ownerDB);
    await assertSucceeds(updateDoc(doc(ownerDB, `groups/${groupId}`), {
      name: "変更後",
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(outsiderDB, `groups/${groupId}`), {
      name: "不正な変更",
      updatedAt: serverTimestamp(),
    }));
  });

  await t.test("FCM tokens cannot be added to member documents", async () => {
    await createGroupAsOwner(ownerDB);
    await assertFails(updateDoc(
      doc(ownerDB, `groups/${groupId}/members/owner-uid`),
      { fcmToken: "secret-token", updatedAt: serverTimestamp() }
    ));
  });

  await t.test("a sender can edit their message but another user cannot", async () => {
    await createGroupAsOwner(ownerDB);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `groups/${groupId}/messages/message-1`), {
        text: "既存メッセージ",
        senderName: "オーナー",
        senderDeviceID: "owner-device",
        senderAuthUID: "owner-uid",
        sentAt: new Date(),
      });
    });
    await assertSucceeds(updateDoc(
      doc(ownerDB, `groups/${groupId}/messages/message-1`),
      { text: "本人による編集", editedAt: serverTimestamp() }
    ));
    await assertFails(deleteDoc(doc(outsiderDB, `groups/${groupId}/messages/message-1`)));
  });

  await t.test("unauthenticated access and unknown collections are denied", async () => {
    await createGroupAsOwner(ownerDB);
    const db = testEnvironment.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `groupCodes/${code}`)));
    await assertFails(getDoc(doc(db, `groups/${groupId}`)));
    await assertFails(setDoc(doc(ownerDB, "unexpected/document"), { value: true }));
  });

  await t.test("membership and counters must be written atomically", async () => {
    await createGroupAsOwner(ownerDB);
    await assertFails(setDoc(doc(memberDB, `groups/${groupId}/members/member-uid`),
      memberData("member-uid", "メンバー", "member-device", code)));
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}`), {
      memberCount: increment(1), updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(joinMember(memberDB));
    await assertFails(deleteDoc(doc(memberDB, `groups/${groupId}/members/member-uid`)));
    await assertFails(deleteDoc(doc(ownerDB, `groups/${groupId}/members/owner-uid`)));
    await assertFails(deleteDoc(doc(memberDB, `groups/${groupId}/members/owner-uid`)));
  });

  await t.test("arrival and leave keep both counters consistent", async () => {
    await createGroupAsOwner(ownerDB);
    await joinMember(memberDB);
    const memberRef = doc(memberDB, `groups/${groupId}/members/member-uid`);
    const groupRef = doc(memberDB, `groups/${groupId}`);
    await assertFails(updateDoc(memberRef, { isArrived: true, updatedAt: serverTimestamp() }));
    const arrival = writeBatch(memberDB);
    arrival.update(memberRef, { isArrived: true, updatedAt: serverTimestamp() });
    arrival.update(groupRef, { arrivedCount: increment(1), updatedAt: serverTimestamp() });
    await assertSucceeds(arrival.commit());
    const badLeave = writeBatch(memberDB);
    badLeave.delete(memberRef);
    badLeave.update(groupRef, { memberCount: increment(-1), updatedAt: serverTimestamp() });
    await assertFails(badLeave.commit());
    const leave = writeBatch(memberDB);
    leave.delete(memberRef);
    leave.update(groupRef, {
      memberCount: increment(-1), arrivedCount: increment(-1), updatedAt: serverTimestamp(),
    });
    await assertSucceeds(leave.commit());
    await assertFails(getDoc(doc(memberDB, `groups/${groupId}`)));
    const group = (await getDoc(doc(ownerDB, `groups/${groupId}`))).data();
    assert.equal(group.memberCount, 1);
    assert.equal(group.arrivedCount, 0);
  });

  await t.test("a member cannot escalate ownership, spoof identity, or change another profile", async () => {
    await createGroupAsOwner(ownerDB);
    await joinMember(memberDB);
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}`), {
      ownerAuthUID: "member-uid", updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}/members/member-uid`), {
      authUID: "owner-uid", updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}/members/owner-uid`), {
      displayName: "変更", updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(ownerDB, `groups/${groupId}`), {
      meetingPlaceURL: "https://example.com/", updatedAt: serverTimestamp(),
    }));
  });

  await t.test("deletion freezes new writes and keeps owner authorization until final cleanup", async () => {
    await createGroupAsOwner(ownerDB);
    await joinMember(memberDB);
    await assertFails(deleteDoc(doc(ownerDB, `groups/${groupId}`)));
    await assertFails(deleteDoc(doc(ownerDB, `groupCodes/${code}`)));
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}`), {
      isDeleting: true, updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(ownerDB, `groups/${groupId}`), {
      isDeleting: true, updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(ownerDB, `groups/${groupId}`), {
      isDeleting: true, updatedAt: serverTimestamp(),
    }));
    await assertFails(joinMember(outsiderDB, "outsider-uid"));
    await assertFails(updateDoc(doc(ownerDB, `groups/${groupId}`), {
      isDeleting: false, updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(memberDB, `groups/${groupId}/messages/late`), {
      text: "遅い投稿", senderName: "メンバー", senderDeviceID: "member-uid-device",
      senderAuthUID: "member-uid", sentAt: serverTimestamp(),
    }));
    await assertFails(deleteDoc(doc(ownerDB, `groups/${groupId}/members/owner-uid`)));
    await assertSucceeds(deleteDoc(doc(ownerDB, `groups/${groupId}/members/member-uid`)));
    await assertSucceeds(getDocs(collection(ownerDB, `groups/${groupId}/messages`)));
    const final = writeBatch(ownerDB);
    final.delete(doc(ownerDB, `groups/${groupId}/members/owner-uid`));
    final.delete(doc(ownerDB, `groupCodes/${code}`));
    final.delete(doc(ownerDB, `groups/${groupId}`));
    await assertSucceeds(final.commit());
    await assertFails(getDocs(collection(memberDB, `groups/${groupId}/messages`)));
  });

  await t.test("orphaned or forged member documents do not authorize message reads", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `groups/${groupId}/members/member-uid`),
        memberData("member-uid", "メンバー", "member-device"));
      await setDoc(doc(db, `groups/${groupId}/messages/orphan`), { text: "残存データ" });
    });
    await assertFails(getDocs(collection(memberDB, `groups/${groupId}/messages`)));
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `groups/${groupId}`), { ownerAuthUID: "owner-uid" });
      await updateDoc(doc(context.firestore(), `groups/${groupId}/members/member-uid`), {
        authUID: "another-uid",
      });
    });
    await assertFails(getDocs(collection(memberDB, `groups/${groupId}/messages`)));
  });

  await t.test("legacy members migrate only their own UID and preserve arrival state", async () => {
    await createGroupAsOwner(ownerDB);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `groups/${groupId}/members/legacy-device`), {
        ...memberData("member-uid", "旧メンバー", "legacy-device"),
        isArrived: true, fcmToken: "legacy-test-token",
      });
    });
    await assertFails(setDoc(doc(outsiderDB, `groups/${groupId}/members/outsider-uid`),
      memberData("outsider-uid", "偽メンバー", "legacy-device")));
    const batch = writeBatch(memberDB);
    batch.set(doc(memberDB, `groups/${groupId}/members/member-uid`), {
      ...memberData("member-uid", "メンバー", "legacy-device"), isArrived: true,
    });
    batch.delete(doc(memberDB, `groups/${groupId}/members/legacy-device`));
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDoc(doc(memberDB, `groups/${groupId}`)));
    const profile = (await getDoc(doc(memberDB, `groups/${groupId}/members/member-uid`))).data();
    assert.equal("fcmToken" in profile, false);
  });

  await t.test("existing token removal and profile updates are permitted", async () => {
    await createGroupAsOwner(ownerDB);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${groupId}/members/owner-uid`), {
        fcmToken: "old-test-token",
      });
    });
    await assertSucceeds(updateDoc(doc(ownerDB, `groups/${groupId}/members/owner-uid`), {
      fcmToken: deleteField(), displayName: "新しい名前", updatedAt: serverTimestamp(),
    }));
  });

  await t.test("a legacy message can be edited by its verified member only", async () => {
    await createGroupAsOwner(ownerDB);
    await joinMember(memberDB);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `groups/${groupId}/messages/legacy`), {
        text: "旧投稿", senderName: "オーナー", senderDeviceID: "owner-device", sentAt: new Date(),
      });
    });
    await assertSucceeds(updateDoc(doc(ownerDB, `groups/${groupId}/messages/legacy`), {
      text: "本人による編集", editedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(memberDB, `groups/${groupId}/messages/legacy`), {
      text: "別人による編集", editedAt: serverTimestamp(),
    }));
  });

  await t.test("oversized input and unexpected profile fields are rejected", async () => {
    await createGroupAsOwner(ownerDB);
    await assertFails(updateDoc(doc(ownerDB, `groups/${groupId}/members/owner-uid`), {
      displayName: "a".repeat(41), updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(ownerDB, `groups/${groupId}/messages/long`), {
      text: "a".repeat(1001), senderName: "オーナー", senderDeviceID: "owner-device",
      senderAuthUID: "owner-uid", sentAt: serverTimestamp(),
    }));
    const profile = memberData("member-uid", "メンバー", "member-device", code);
    profile.admin = true;
    const batch = writeBatch(memberDB);
    batch.set(doc(memberDB, `groups/${groupId}/members/member-uid`), profile);
    batch.update(doc(memberDB, `groups/${groupId}`), {
      memberCount: increment(1), updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  await t.test("an owner can delete 200 child documents in one batch and then finish", async () => {
    await createGroupAsOwner(ownerDB);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const batch = writeBatch(db);
      for (let i = 0; i < 201; i++) {
        batch.set(doc(db, `groups/${groupId}/messages/seed-${i}`), { text: "テスト" });
      }
      await batch.commit();
    });
    await updateDoc(doc(ownerDB, `groups/${groupId}`), {
      isDeleting: true, updatedAt: serverTimestamp(),
    });
    const docs = (await getDocs(collection(ownerDB, `groups/${groupId}/messages`))).docs;
    const batch = writeBatch(ownerDB);
    docs.slice(0, 200).forEach((snapshot) => batch.delete(snapshot.ref));
    await assertSucceeds(batch.commit());
    await assertSucceeds(deleteDoc(docs[200].ref));
    const final = writeBatch(ownerDB);
    final.delete(doc(ownerDB, `groups/${groupId}/members/owner-uid`));
    final.delete(doc(ownerDB, `groupCodes/${code}`));
    final.delete(doc(ownerDB, `groups/${groupId}`));
    await assertSucceeds(final.commit());
  });
});
