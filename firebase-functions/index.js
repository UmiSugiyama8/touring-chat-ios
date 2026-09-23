const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

admin.initializeApp();

exports.notifyGroupMessage = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data && event.data.data();
    if (!message) {
      return;
    }

    const groupId = event.params.groupId;
    const groupSnapshot = await admin.firestore().collection("groups").doc(groupId).get();
    const groupName = groupSnapshot.get("name") || "ツーリング";
    const senderDeviceID = message.senderDeviceID || "";

    const membersSnapshot = await admin
      .firestore()
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();

    const tokens = [];
    membersSnapshot.forEach((doc) => {
      const member = doc.data();
      if (member.deviceID === senderDeviceID) {
        return;
      }
      if (member.fcmToken) {
        tokens.push(member.fcmToken);
      }
    });

    if (tokens.length === 0) {
      return;
    }

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: groupName,
        body: `${message.senderName || "メンバー"}: ${message.text || ""}`,
      },
      data: {
        groupId,
        messageId: event.params.messageId,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });
  }
);
