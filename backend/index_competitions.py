from app.retrieval import get_retrieval_service


if __name__ == "__main__":
    result = get_retrieval_service().build_index()
    print(f"索引完成：{result}")

