import boto3
import uuid
import logging
from config import settings

# Configuración de logging para trazabilidad en entornos de ejecución (CloudWatch/Loki)
logger = logging.getLogger(__name__)

polly_client = boto3.client('polly', region_name=settings.AWS_REGION)
s3_client = boto3.client('s3', region_name=settings.AWS_REGION)

def process_single_tts(text: str, voice: str, format: str, folder_path: str) -> bool:
    """
    Sintetiza un fragmento de texto a audio mediante AWS Polly y almacena 
    el resultado en un bucket de Amazon S3.

    Args:
        text (str): Contenido textual a convertir en audio.
        voice (str): Identificador de la voz de AWS Polly (e.g., 'Mia', 'Andres').
        format (str): Formato de salida del archivo (e.g., 'mp3', 'ogg_vorbis').
        folder_path (str): Ruta de destino (prefijo) en el bucket de S3.

    Returns:
        bool: Retorna True si la síntesis y el almacenamiento fueron exitosos, 
              False en caso de error durante el proceso.
    """
    try:
        # Ejecución de la síntesis de voz en el motor de AWS Polly
        response = polly_client.synthesize_speech(
            Text=text,
            OutputFormat=format,
            VoiceId=voice
        )
        
        # identificador (UUID) para el objeto en S3
        object_key = f"{folder_path}{uuid.uuid4()}.{format}"
        
        # Transferencia del flujo de datos (AudioStream) directamente a Amazon S3
        s3_client.put_object(
            Bucket=settings.S3_BUCKET_NAME,
            Key=object_key,
            Body=response['AudioStream'].read(),
            ContentType=f"audio/{format}"
        )
        
        return True

    except Exception as e:
        # Registro del error detallado para auditoría
        logger.error(f"Falla en el proceso de síntesis/almacenamiento para la ruta {folder_path}: {e}")
        return False