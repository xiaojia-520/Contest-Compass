ARG PYTHON_IMAGE=docker.m.daocloud.io/library/python:3.11-slim
FROM ${PYTHON_IMAGE}
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG TORCH_WHEEL_URL=https://mirrors.nju.edu.cn/pytorch/whl/cpu/torch-2.14.0%2Bcpu-cp311-cp311-manylinux_2_28_x86_64.whl
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app:/app/backend
WORKDIR /app
COPY backend/requirements.txt /app/backend/requirements.txt
RUN python -m pip install --no-cache-dir \
    --index-url "${PIP_INDEX_URL}" \
    "${TORCH_WHEEL_URL}"
RUN python -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" -r /app/backend/requirements.txt
COPY backend/ /app/backend/
COPY alembic.ini saikr_crawler.py schema.sql /app/
COPY frontend/build/web /app/frontend/build/web
CMD ["uvicorn", "app.main:app", "--app-dir", "backend", "--host", "0.0.0.0", "--port", "8000"]
