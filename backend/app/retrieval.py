from __future__ import annotations

from functools import lru_cache

from qdrant_client import QdrantClient, models

from .competition import CompetitionRepository
from .config import get_settings


class RetrievalService:
    def __init__(self) -> None:
        self.settings = get_settings()
        self.repo = CompetitionRepository()
        self.client = QdrantClient(url=self.settings.qdrant_url, timeout=10)
        self._encoder = None

    @property
    def encoder(self):
        if self._encoder is None:
            from sentence_transformers import SentenceTransformer

            self._encoder = SentenceTransformer(str(self.settings.embedding_model_path), local_files_only=True)
        return self._encoder

    def collection_ready(self) -> bool:
        try:
            return self.client.collection_exists(self.settings.qdrant_collection)
        except Exception:
            return False

    def build_index(self) -> dict:
        rows = self.repo.list_for_index()
        vectors = self.encoder.encode(
            [row["embedding_text"] for row in rows],
            batch_size=32,
            normalize_embeddings=True,
            show_progress_bar=True,
        )
        collection = self.settings.qdrant_collection
        if self.client.collection_exists(collection):
            self.client.delete_collection(collection)
        self.client.create_collection(
            collection_name=collection,
            vectors_config=models.VectorParams(size=512, distance=models.Distance.COSINE),
        )
        points = [
            models.PointStruct(
                id=row["contest_id"],
                vector=vector.tolist(),
                payload={
                    "contest_id": row["contest_id"],
                    "contest_name": row["contest_name"],
                    "register_end_at": row["register_end_at"],
                    "contest_start_at": row["contest_start_at"],
                },
            )
            for row, vector in zip(rows, vectors, strict=True)
        ]
        for offset in range(0, len(points), 128):
            self.client.upsert(collection_name=collection, points=points[offset : offset + 128], wait=True)
        return {"collection": collection, "indexed": len(points), "vector_size": 512}

    def search(self, query: str, limit: int = 12) -> list[dict]:
        eligible = self.repo.eligible_ids()
        ids: list[int] = []
        if self.collection_ready():
            try:
                vector = self.encoder.encode(query, normalize_embeddings=True).tolist()
                result = self.client.query_points(
                    collection_name=self.settings.qdrant_collection,
                    query=vector,
                    limit=max(60, limit * 4),
                    with_payload=False,
                )
                ids = [int(point.id) for point in result.points if int(point.id) in eligible][:limit]
            except Exception:
                ids = []
        if len(ids) < limit:
            fallback = self.repo.keyword_candidates(query, limit=limit)
            ids.extend(item for item in fallback if item not in ids and item in eligible)
        return self.repo.get_many(ids[:limit])


@lru_cache
def get_retrieval_service() -> RetrievalService:
    return RetrievalService()

