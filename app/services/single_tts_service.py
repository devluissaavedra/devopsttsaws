import boto3
import uuid
import logging
from config import settings
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger(__name__)

# Se usa una sesión global, es más eficiente en AWS
session = boto3.Session(region_name=settings.AWS_REGION)
polly_client = session.client('polly')
s3_client = session.client('s3')

def process_single_tts(text: str, voice: str, format: str, folder_path: str) -> bool:
    try:
        # 1. Síntesis de voz
        response = polly_client.synthesize_speech(
            Text=text,
            OutputFormat=format,
            VoiceId=voice,
            Engine='neural' # Las voces neurales suenan mucho mejor
        )
        
        object_key = f"{folder_path}{uuid.uuid4()}.{format}"
        
        # 2. Subida optimizada
        # Se usa 'upload_fileobj' porque acepta el stream directamente sin cargar todo en RAM
        s3_client.upload_fileobj(
            Fileobj=response['AudioStream'],
            Bucket=settings.S3_BUCKET_NAME,
            Key=object_key,
            ExtraArgs={'ContentType': f"audio/{format}"}
        )
        return True

    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error de AWS en {folder_path}: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"Error inesperado: {str(e)}")
        return False