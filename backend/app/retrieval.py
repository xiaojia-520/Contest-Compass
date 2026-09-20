from __future__ import annotations

from functools import lru_cache
from datetime import datetime, timezone
import uuid

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
            return self._active_collection() is not None
        except Exception:
            return False

    def _alias_target(self) -> str | None:
        aliases = self.client.get_aliases().aliases
        for item in aliases:
            if item.alias_name == self.settings.qdrant_alias:
                return item.collection_name
        return None

    def _active_collection(self) -> str | None:
        if self._alias_target():
            return self.settings.qdrant_alias
        if self.client.collection_exists(self.settings.qdrant_collection):
            return self.settings.qdrant_collection
        return None

    def vector_count(self) -> int | None:
        collection = self._active_collection()
        if not collection:
            return None
        return int(self.client.count(collection_name=collection, exact=True).count)

    def _points(self, rows: list[dict]) -> list[models.PointStruct]:
        if not rows:
            return []
        vectors = self.encoder.encode(
            [row["embedding_text"] for row in rows],
            batch_size=32,
            normalize_embeddings=True,
            show_progress_bar=len(rows) > 64,
        )
        return [
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

    def _upsert_points(self, collection: str, points: list[models.PointStruct]) -> None:
        for offset in range(0, len(points), 128):
            self.client.upsert(collection_name=collection, points=points[offset : offset + 128], wait=True)

    def build_index(self) -> dict:
        rows = self.repo.list_for_index()
        points = self._points(rows)
        vector_size = int(self.encoder.get_embedding_dimension() or 0)
        if not vector_size:
            raise RuntimeError("无法确定向量模型维度")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
        collection = f"{self.settings.qdrant_collection}_{stamp}_{uuid.uuid4().hex[:6]}"
        self.client.create_collection(
            collection_name=collection,
            vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE),
        )
        try:
            self._upsert_points(collection, points)
            actual = int(self.client.count(collection_name=collection, exact=True).count)
            if actual != len(points):
                raise RuntimeError(f"索引数量校验失败：期望 {len(points)}，实际 {actual}")

            old_target = self._alias_target()
            operations: list = []
            if old_target:
                operations.append(
                    models.DeleteAliasOperation(
                        delete_alias=models.DeleteAlias(alias_name=self.settings.qdrant_alias)
                    )
                )
            operations.append(
                models.CreateAliasOperation(
                    create_alias=models.CreateAlias(
                        collection_name=collection,
                        alias_name=self.settings.qdrant_alias,
                    )
                )
            )
            self.client.update_collection_aliases(change_aliases_operations=operations)

            legacy = self.settings.qdrant_collection
            for old in {old_target, legacy} - {None, collection}:
                if self.client.collection_exists(old):
                    self.client.delete_collection(old)
        except Exception:
            if self.client.collection_exists(collection) and self._alias_target() != collection:
                self.client.delete_collection(collection)
            raise
        return {"collection": collection, "indexed": len(points), "vector_size": vector_size}

    def sync_index(self, changed_ids: list[int] | None = None) -> dict:
        collection = self._active_collection()
        if not collection:
            result = self.build_index()
            return {"created": result["indexed"], "updated": 0, "deleted": 0, **result}

        existing: set[int] = set()
        offset = None
        while True:
            points, offset = self.client.scroll(
                collection_name=collection,
                limit=256,
                offset=offset,
                with_payload=False,
                with_vectors=False,
            )
            existing.update(int(point.id) for point in points)
            if offset is None:
                break

        eligible = self.repo.eligible_ids()
        delete_ids = sorted(existing - eligible)
        if delete_ids:
            self.client.delete(collection_name=collection, points_selector=delete_ids, wait=True)

        changed = set(int(item) for item in (changed_ids or []))
        upsert_ids = sorted((changed & eligible) | (eligible - existing))
        rows = self.repo.get_for_index(upsert_ids)
        points = self._points(rows)
        self._upsert_points(collection, points)
        created = len(set(upsert_ids) - existing)
        return {
            "collection": collection,
            "created": created,
            "updated": len(points) - created,
            "deleted": len(delete_ids),
            "vector_count": self.vector_count(),
        }

    def search(self, query: str, limit: int = 12) -> list[dict]:
        eligible = self.repo.eligible_ids()
        ids: list[int] = []
        collection = self._active_collection()
        if collection:
            try:
                vector = self.encoder.encode(query, normalize_embeddings=True).tolist()
                result = self.client.query_points(
                    collection_name=collection,
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
