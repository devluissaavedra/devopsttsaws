import uuid
from fastapi import FastAPI, BackgroundTasks
from schemas.schemas import TTSRequest
from services.tts_service import process_tts
from config import settings

app = FastAPI(title="DevOps TTS API")

@app.get("/health")
def health():
    return {"ok"}

@app.post("/tts", status_code=202) # 202 significa "Accepted" (proceso en curso)
async def tts(request: TTSRequest, background_tasks: BackgroundTasks):
    # Se genera un ID de proyecto único
    project_id = str(uuid.uuid4())
    folder_path = f"audios/{project_id}/"

    background_tasks.add_task(
        process_tts, 
        request.texts, 
        request.voice, 
        request.format, 
        folder_path
    )

    return {
        "status": "processing",
        "project_id": project_id,
        "s3_url": f"https://{settings.S3_BUCKET_NAME}.s3.{settings.AWS_REGION}.amazonaws.com/{folder_path}",
        "details": {
            "chunks": len(request.texts),
            "voice": request.voice
        }
    }