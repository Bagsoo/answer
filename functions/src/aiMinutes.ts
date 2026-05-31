import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import { GoogleGenerativeAI } from "@google/generative-ai";
import axios from "axios";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import FormData from "form-data";

// 환경 설정
const groqApiKey = defineSecret("GROQ_API_KEY");
const geminiApiKey = defineSecret("GEMINI_API_KEY");

// 저장된 파일 트리거 (Firebase Storage v2)
export const onAiMinutesAudioUploaded = onObjectFinalized(
  {
    // bucket 옵션을 제거하면 프로젝트 기본 버킷을 사용합니다.
    secrets: [groqApiKey, geminiApiKey],
  },
  async (event) => {
    console.log("Function triggered. File path:", event.data.name);
    const db = admin.firestore(); // 함수 실행 시점에 초기화된 admin 사용
    const filePath = event.data.name;

    // 경로: chat_rooms/{roomId}/audio/{filename}.m4a
    if (!filePath || !filePath.includes("/audio/")) {
      console.log("Skipping: Not a valid audio file path");
      return;
    }

    const pathParts = filePath.split("/");
    const roomId = pathParts[1];
    console.log("Room ID extracted:", roomId);

    // 1. Job 생성 및 상태 초기화
    // 파일 메타데이터에서 jobId 추출 시도
    const fileMetadata = event.data.metadata;
    const jobId = fileMetadata?.job_id;
    console.log("Metadata found, jobId:", jobId);

    const jobRef = jobId 
      ? db.collection("ai_jobs").doc(jobId) 
      : db.collection("ai_jobs").doc();
      
    console.log("Job doc ID:", jobRef.id);
    
    if (jobId) {
      console.log("Existing job found, updating status to processing");
      await jobRef.update({
        status: "processing",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      console.log("No existing job found, creating new one");
      await jobRef.set({
        jobId: jobRef.id,
        roomId: roomId,
        audioUrl: filePath,
        status: "processing",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 로컬 임시 파일 경로
    const tempFilePath = path.join(os.tmpdir(), path.basename(filePath));
    const bucket = admin.storage().bucket(event.data.bucket);

    try {
      // 파일 다운로드
      console.log("Downloading file to:", tempFilePath);
      await bucket.file(filePath).download({ destination: tempFilePath });
      console.log("File downloaded successfully");

      // 2. Groq STT 호출 (Whisper)
      console.log("Starting transcription...");
      const fullText = await transcribeAudio(tempFilePath, groqApiKey.value());
      console.log("Transcription completed. Length:", fullText.length);

      // 3. Gemini 요약 호출
      console.log("Starting summarization...");
      const summary = await summarizeText(fullText, geminiApiKey.value());
      console.log("Summarization completed");

      // 4. Firestore Transaction: 쿼터 관리 및 결과 업데이트
      // 작업 성공 후 count 증가
      const roomDoc = await db.collection("chat_rooms").doc(roomId).get();
      const groupId = roomDoc.data()?.ref_group_id;

      console.log("Group ID found:", groupId);
      if (!groupId) throw new Error("Group ID not found");

      const now = new Date();
      const monthId = `${now.getFullYear()}_${(now.getMonth() + 1).toString().padStart(2, '0')}`;
      const usageRef = db.collection("groups").doc(groupId).collection("usage").doc("months").collection(monthId).doc(monthId);

      await db.runTransaction(async (tx) => {
        console.log("Running usage transaction...");
        const usageSnap = await tx.get(usageRef);
        const currentCount = usageSnap.exists ? (usageSnap.data()?.count || 0) : 0;

        if (currentCount >= 10) {
          throw new Error("Quota exceeded");
        }

        tx.set(usageRef, {
          count: currentCount + 1,
          month: monthId,
          last_used_at: admin.firestore.FieldValue.serverTimestamp(),
          last_job_id: jobRef.id
        }, { merge: true });

        tx.update(jobRef, {
          status: "completed",
          result: { summary, fullText },
          completedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log("Transaction committed successfully");
      });

    } catch (error) {
      console.error("AI Processing failed:", error);
      await jobRef.update({
        status: "failed",
        errorMessage: (error as Error).message
      });
    } finally {
      // 임시 파일 삭제
      if (fs.existsSync(tempFilePath)) {
        console.log("Deleting temp file...");
        fs.unlinkSync(tempFilePath);
      }
    }
  }
);

async function transcribeAudio(tempFilePath: string, apiKey: string): Promise<string> {
  const formData = new FormData();
  formData.append("file", fs.createReadStream(tempFilePath));
  formData.append("model", "whisper-large-v3-turbo");

  const response = await axios.post("https://api.groq.com/openai/v1/audio/transcriptions", formData, {
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      ...formData.getHeaders()
    }
  });
  return response.data.text;
}

async function summarizeText(text: string, apiKey: string): Promise<string> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
  const result = await model.generateContent(`회의록을 요약해주세요: ${text}`);
  return result.response.text();
}
