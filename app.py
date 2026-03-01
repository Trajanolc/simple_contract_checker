from fastapi import FastAPI
from fastapi.responses import RedirectResponse

from controllers.analyze_controller import router as analyze_router

app = FastAPI(
    title="Simple Contract Checker",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)
app.include_router(analyze_router)


@app.get("/")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/swagger", include_in_schema=False)
async def swagger_redirect() -> RedirectResponse:
    return RedirectResponse(url="/docs")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host="0.0.0.0", port=8003, reload=True)
