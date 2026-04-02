const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function testQuery() {
  try {
    // We just test the query shape. We don't need a real UID or GroupID if it's an index error.
    // If it's an index error, it fails immediately before checking data presence.
    console.log("Testing query shape...");
    const snap = await db.collection('chat_rooms')
      .where('ref_group_id', '==', 'dummy_group_id')
      .where('member_ids', 'array-contains', 'dummy_user_id')
      .orderBy('last_time', 'desc')
      .get();
      
    console.log("Query succeeded! Found docs:", snap.docs.length);
  } catch (e) {
    console.error("Query failed:", e.message);
  }
}

testQuery();
