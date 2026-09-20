from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from .competition import CompetitionRepository
from .database import get_db
from .llm_service import LLMService, project_context
from .models import ChatMessage, ModelConfig, Project, RecommendationRun, UsageRecord, User
from .retrieval import get_retrieval_service
from .schemas import (
    ChatMessageOut,
    ChatRequest,
    ChatResponse,
    CompetitionOut,
    LoginRequest,
    ModelConfigIn,
    ModelConfigOut,
    ProjectCreate,
    ProjectOut,
    ProjectUpdate,
    RecommendationOut,
    TokenOut,
    UsageOut,
    UserCreate,
    UserOut,
)
from .security import create_access_token, encrypt_secret, get_current_user, hash_password, verify_password


router = APIRouter(prefix="/api")


@router.get("/health")
def health() -> dict:
    settings = get_retrieval_service().settings
    return {
        "status": "ok",
        "service": "赛智荐 API",
        "competition_db": settings.competition_db_path.exists(),
        "vector_index": get_retrieval_service().collection_ready(),
    }


@router.post("/auth/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Session = Depends(get_db)) -> TokenOut:
    exists = db.scalar(
        select(User).where(
            or_(User.username == payload.username, User.email == payload.email if payload.email else False)
        )
    )
    if exists:
        raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")
    user = User(username=payload.username, email=payload.email or None, password_hash=hash_password(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenOut(access_token=create_access_token(user.id), user=UserOut.model_validate(user))


@router.post("/auth/login", response_model=TokenOut)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenOut:
    user = db.scalar(select(User).where(or_(User.username == payload.account, User.email == payload.account)))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="账号或密码错误")
    return TokenOut(access_token=create_access_token(user.id), user=UserOut.model_validate(user))


@router.get("/auth/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)) -> User:
    return user


@router.get("/model-config", response_model=ModelConfigOut | None)
def get_model_config(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    value = db.scalar(select(ModelConfig).where(ModelConfig.user_id == user.id))
    if not value:
        return None
    return ModelConfigOut(
        provider=value.provider,
        model_name=value.model_name,
        api_base=value.api_base,
        has_api_key=bool(value.encrypted_api_key),
        updated_at=value.updated_at,
    )


@router.put("/model-config", response_model=ModelConfigOut)
def save_model_config(
    payload: ModelConfigIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ModelConfigOut:
    value = db.scalar(select(ModelConfig).where(ModelConfig.user_id == user.id))
    if not value:
        value = ModelConfig(user_id=user.id, provider=payload.provider, model_name=payload.model_name)
        db.add(value)
    value.provider = payload.provider
    value.model_name = payload.model_name
    value.api_base = payload.api_base
    if payload.api_key:
        value.encrypted_api_key = encrypt_secret(payload.api_key)
    value.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(value)
    return ModelConfigOut(
        provider=value.provider,
        model_name=value.model_name,
        api_base=value.api_base,
        has_api_key=bool(value.encrypted_api_key),
        updated_at=value.updated_at,
    )


@router.post("/model-config/test")
async def test_model_config(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    try:
        answer = await LLMService(db, user.id).test()
        return {"ok": True, "message": answer}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"模型连接失败：{type(exc).__name__}")


def owned_project(project_id: int, user: User, db: Session) -> Project:
    project = db.scalar(select(Project).where(Project.id == project_id, Project.owner_id == user.id))
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")
    return project


@router.get("/projects", response_model=list[ProjectOut])
def list_projects(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(Project).where(Project.owner_id == user.id).order_by(Project.updated_at.desc())))


@router.post("/projects", response_model=ProjectOut, status_code=status.HTTP_201_CREATED)
def create_project(payload: ProjectCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    project = Project(owner_id=user.id, **payload.model_dump())
    db.add(project)
    db.commit()
    db.refresh(project)
    return project


@router.get("/projects/{project_id}", response_model=ProjectOut)
def get_project(project_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return owned_project(project_id, user, db)


@router.put("/projects/{project_id}", response_model=ProjectOut)
def update_project(
    project_id: int,
    payload: ProjectUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = owned_project(project_id, user, db)
    for key, value in payload.model_dump().items():
        setattr(project, key, value)
    project.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(project)
    return project


@router.post("/projects/{project_id}/markdown", response_model=ProjectOut)
async def upload_markdown(
    project_id: int,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = owned_project(project_id, user, db)
    if not file.filename or not file.filename.lower().endswith((".md", ".markdown")):
        raise HTTPException(status_code=400, detail="仅支持 .md 或 .markdown 文件")
    content = await file.read(2_000_001)
    if len(content) > 2_000_000:
        raise HTTPException(status_code=413, detail="Markdown 文件不能超过 2 MB")
    try:
        project.markdown_content = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise HTTPException(status_code=400, detail="Markdown 文件必须使用 UTF-8 编码")
    project.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(project)
    return project


def recommendation_response(run: RecommendationRun) -> RecommendationOut:
    candidates = CompetitionRepository().get_many(run.candidate_contest_ids)
    return RecommendationOut(
        id=run.id,
        project_id=run.project_id,
        status=run.status,
        report=run.report,
        candidates=[CompetitionOut(**item) for item in candidates],
        created_at=run.created_at,
    )


@router.get("/projects/{project_id}/recommendations/latest", response_model=RecommendationOut | None)
def latest_recommendation(
    project_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    owned_project(project_id, user, db)
    run = db.scalar(
        select(RecommendationRun)
        .where(RecommendationRun.project_id == project_id)
        .order_by(RecommendationRun.created_at.desc())
    )
    return recommendation_response(run) if run else None


@router.post("/projects/{project_id}/recommend", response_model=RecommendationOut)
async def recommend(
    project_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = owned_project(project_id, user, db)
    query = project_context(project)
    candidates = get_retrieval_service().search(query, limit=12)
    if not candidates:
        raise HTTPException(status_code=503, detail="没有找到可报名或即将开始的比赛")
    try:
        report = await LLMService(db, user.id, project.id).recommend(project, candidates)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"AI 生成失败：{type(exc).__name__}")
    run = RecommendationRun(
        project_id=project.id,
        report=report,
        candidate_contest_ids=[item["contest_id"] for item in candidates],
    )
    db.add(run)
    db.commit()
    db.refresh(run)
    return recommendation_response(run)


@router.get("/projects/{project_id}/messages", response_model=list[ChatMessageOut])
def list_messages(
    project_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    owned_project(project_id, user, db)
    return list(db.scalars(select(ChatMessage).where(ChatMessage.project_id == project_id).order_by(ChatMessage.id)))


@router.post("/projects/{project_id}/chat", response_model=ChatResponse)
async def chat(
    project_id: int,
    payload: ChatRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = owned_project(project_id, user, db)
    existing = list(
        db.scalars(select(ChatMessage).where(ChatMessage.project_id == project_id).order_by(ChatMessage.id.desc()).limit(16))
    )
    history = [{"role": item.role, "content": item.content} for item in reversed(existing)]
    latest = db.scalar(
        select(RecommendationRun)
        .where(RecommendationRun.project_id == project_id)
        .order_by(RecommendationRun.created_at.desc())
    )
    ids = latest.candidate_contest_ids if latest else []
    competitions = CompetitionRepository().get_many(ids[:12])
    try:
        answer = await LLMService(db, user.id, project.id).chat(project, history, payload.message, competitions)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"AI 回复失败：{type(exc).__name__}")
    user_message = ChatMessage(project_id=project_id, role="user", content=payload.message, sources=[])
    assistant = ChatMessage(
        project_id=project_id,
        role="assistant",
        content=answer,
        sources=[{"contest_id": item["contest_id"], "name": item["contest_name"], "url": item["source_url"]} for item in competitions[:5]],
    )
    db.add_all([user_message, assistant])
    db.commit()
    db.refresh(user_message)
    db.refresh(assistant)
    return ChatResponse(user_message=user_message, assistant_message=assistant)


@router.get("/usage", response_model=list[UsageOut])
def usage(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(UsageRecord).where(UsageRecord.user_id == user.id).order_by(UsageRecord.id.desc()).limit(100)))

