from pydantic import BaseModel
from typing import List

class TTSRequest(BaseModel):
    texts: List[str]
    voice: str
    format: str