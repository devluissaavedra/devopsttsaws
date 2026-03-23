from fastapi import FastAPI
from schemas.schemas import TTSRequest
from services.tts_service import process_tts
from fastapi import BackgroundTasks

app = FastAPI()

@app.get("/health")
def health():
    return {"ok"}

@app.post("/tts")
def tts(request: TTSRequest, background_tasks: BackgroundTasks):
    # Se crea la carpeta de destino de los archivos.
    project_id = str(uuid.uuid4())
    folder_path = f"audios/{project_id}/"

    # Se manda el proceso pesado al fondo
    background_tasks.add_task(
        process_tts, 
        request.texts, 
        request.voice, 
        request.format, 
        folder_path
    )

    # Se responde 
    return {
        "message": "Processing started",
        "project_folder": f"https://{settings.S3_BUCKET_NAME}.s3.amazonaws.com/{folder_path}",
        "details": {
            "count": len(request.texts),
            "voice_used": request.voice
        }
    }