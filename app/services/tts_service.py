import boto3
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import List

# Inicializar clientes de AWS
polly = boto3.client('polly', region_name=settings.AWS_REGION)
s3 = boto3.client('s3', region_name=settings.AWS_REGION)

def process_single_tts(text: str, voice: str, format: str) -> str:
    response = polly.synthesize_speech(
        Text=text,
        OutputFormat=format,
        VoiceId=voice
    )
    
    # Generar un nombre único para el archivo
    filename = f"audio/{uuid.uuid4()}.{format}"
    
    #Guardar en S3
    s3.put_object(
        Bucket=settings.S3_BUCKET_NAME,
        Key=filename,
        Body=response['AudioStream'].read(),
        ContentType=f"audio/{format}"
    )
    
    # Retornar la URL pública o el path
    return f"https://{settings.S3_BUCKET_NAME}.s3.amazonaws.com/{filename}"


def analyze_and_process(texts: List[str], voice: str, format: str):

    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(
            lambda t: process_single_tts(t, voice, format), 
            texts
        ))
    return results