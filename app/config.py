import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Estas variables las tomará de la instancia de EC2 o del entorno
    AWS_REGION: str = os.getenv("AWS_REGION", "us-east-1")
    S3_BUCKET_NAME: str = os.getenv("S3_BUCKET_NAME", "devops-tts-audios-luis-2026")

    class Config:
        env_file = ".env"

settings = Settings()