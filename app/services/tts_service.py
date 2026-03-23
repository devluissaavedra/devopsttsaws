import logging
from typing import List
from concurrent.futures import ThreadPoolExecutor
from services.single_tts_service import process_single_tts

# Configuración de logging profesional
logger = logging.getLogger(__name__)

def process_tts(texts: List[str], voice: str, format: str, folder_path: str) -> bool:
    """
    Orquesta la conversión de texto a voz de forma paralela.
    
    Mapeo directo sobre el pool de hilos para procesar la lista 
    de textos de manera concurrente.
    """
    
    # Se define el pool de hilos para ejecución paralela
    with ThreadPoolExecutor(max_workers=5) as executor:
        try:
            results = executor.map(
                lambda t: process_single_tts(t, voice, format, folder_path), 
                texts
            )
            
            success = all(results)

        except Exception as exc:
            logger.error(f"Error crítico en la orquestación del proyecto {folder_path}: {exc}")
            success = False

    if success:
        logger.info(f"Lote finalizado exitosamente en: {folder_path}")
    else:
        logger.warning(f"El lote en {folder_path} finalizó con errores parciales.")

    return success