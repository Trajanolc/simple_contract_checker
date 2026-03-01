from fastapi import APIRouter, File, HTTPException, UploadFile

from models.schemas import AnalyzeResponse
from services.analyzer_service import ContractAnalyzer
from services.parser_service import extract_text

router = APIRouter()
analyzer = ContractAnalyzer()


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(file: UploadFile = File(...)) -> AnalyzeResponse:
    filename = file.filename or "uploaded.txt"
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")

    try:
        text = extract_text(content, filename)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if not text.strip():
        raise HTTPException(status_code=400, detail="No readable text found in file")

    report = await analyzer.analyze(text)
    return AnalyzeResponse(filename=filename, report=report)
