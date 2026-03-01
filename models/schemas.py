from dataclasses import dataclass

from pydantic import BaseModel, Field


class Finding(BaseModel):
    sentence: str
    issue: str
    suggestion: str
    severity: str
    evidence: str = ""


class AnalyzeReport(BaseModel):
    language: str
    jurisdiction: str
    findings: list[Finding] = Field(default_factory=list)
    summary: str


class AnalyzeResponse(BaseModel):
    filename: str
    report: AnalyzeReport


class Agent1Output(BaseModel):
    language: str
    jurisdiction: str


class Agent2Output(BaseModel):
    findings: list[Finding]
    summary: str


@dataclass
class SentenceItem:
    text: str
    position: int
