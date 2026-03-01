# Simple Contract Checker App

Small FastAPI service with one endpoint:
- Accepts `.docx`, `.pdf`, or `.txt`
- Agent 1 detects language and jurisdiction
- Agent 2 finds vague/ambiguous sentences and suggests clearer wording
- Returns a JSON report

## Run

```bash
cd simple_contract_app
uv sync
cp .env.example .env
uv run uvicorn app:app --reload --port 8003
```

## Endpoint

`POST /analyze`

## API Docs (Swagger)

- Swagger UI: `http://localhost:8003/docs`
- Swagger alias: `http://localhost:8003/swagger`
- OpenAPI JSON: `http://localhost:8003/openapi.json`
- ReDoc: `http://localhost:8003/redoc`

Form field:
- `file`: contract file (`txt`, `pdf`, `docx`)

Example:

```bash
curl -X POST "http://localhost:8003/analyze" \
  -F "file=@/path/to/contract.txt"
```

## Notes

- If `OPENAI_API_KEY` is configured, the app uses OpenAI for both agents with `temperature=0`.
- If no API key is configured, it uses a deterministic fallback heuristic.
