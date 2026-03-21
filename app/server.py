from fastapi import FastAPI
from schemas.schemas import TTSRequest
from services.tts_service import process_tts

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/tts")
def tts(request: TTSRequest):
    # 1. Los datos YA están validados aquí gracias a Pydantic.
    # 2. Ahora los usamos de forma efectiva llamando a un servicio.
    
    result = process_tts(
        texts=request.texts, 
        voice=request.voice, 
        format=request.format
    )
    
    return {
        "message": "Procesamiento iniciado",
        "audio_url": result.url,  # Se espera devolver una URL de S3
        "details": {
            "count": len(request.texts),
            "voice_used": request.voice
        }
    }