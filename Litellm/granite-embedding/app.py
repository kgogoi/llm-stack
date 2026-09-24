import os
from typing import List, Any, Optional
from fastapi import FastAPI
from pydantic import BaseModel, ConfigDict
from sentence_transformers import SentenceTransformer
import tiktoken

MODEL_PATH = os.getenv("MODEL_PATH", "/model")

app = FastAPI(title="IBM Granite Embedding Service")
print(f"Loading IBM Granite model from: {MODEL_PATH}...")
model = SentenceTransformer(MODEL_PATH)
print("IBM Granite Model loaded successfully!")

try:
    enc = tiktoken.get_encoding("cl100k_base")
except Exception:
    enc = None

class EmbeddingRequest(BaseModel):
    model_config = ConfigDict(extra="allow")
    input: Any
    model: Optional[str] = "granite-embedding-125m"

@app.get("/health")
def health():
    return {"status": "ok", "model": "ibm-granite/granite-embedding-125m-english"}

def process_single_input(item) -> str:
    if isinstance(item, str):
        return item
    elif isinstance(item, (list, tuple)):
        if all(isinstance(x, int) for x in item):
            return enc.decode(item) if enc else " ".join(map(str, item))
        elif all(isinstance(x, str) for x in item):
            return " ".join(item)
    return str(item)

@app.post("/v1/embeddings")
def embeddings(req: EmbeddingRequest):
    raw_input = req.input
    inputs: List[str] = []
    
    if isinstance(raw_input, str):
        inputs = [raw_input]
    elif isinstance(raw_input, list):
        if len(raw_input) > 0 and isinstance(raw_input[0], int):
            inputs = [process_single_input(raw_input)]
        else:
            inputs = [process_single_input(item) for item in raw_input]
    else:
        inputs = [str(raw_input)]
        
    embeddings_list = model.encode(inputs, normalize_embeddings=True).tolist()
    data = [{"object": "embedding", "index": i, "embedding": emb} for i, emb in enumerate(embeddings_list)]
    return {
        "object": "list",
        "data": data,
        "model": req.model or "granite-embedding-125m",
        "usage": {"prompt_tokens": 0, "total_tokens": 0}
    }
