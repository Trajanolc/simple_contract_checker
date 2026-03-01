import re

from openai import AsyncOpenAI

from core.config import settings
from models.schemas import Agent1Output, Agent2Output, AnalyzeReport, Finding, SentenceItem


class ContractAnalyzer:
    def __init__(self) -> None:
        self.client = (
            AsyncOpenAI(api_key=settings.openai_api_key)
            if settings.openai_api_key
            else None
        )

    async def analyze(self, text: str) -> AnalyzeReport:
        first = await self._agent1_detect(text)
        second = await self._agent2_find(text=text, language=first.language, jurisdiction=first.jurisdiction)
        return AnalyzeReport(
            language=first.language,
            jurisdiction=first.jurisdiction,
            findings=second.findings[: settings.max_findings],
            summary=second.summary,
        )

    async def _agent1_detect(self, text: str) -> Agent1Output:
        if self.client is None:
            return heuristic_agent1(text)

        prompt = f"""
You are Agent 1.
Task: detect the document language and legal jurisdiction.
Return ONLY JSON:
{{
  "language": "English",
  "jurisdiction": "United States"
}}
If jurisdiction is unclear, use "Unknown".

Document:
\"\"\"{text[:16000]}\"\"\"
"""
        try:
            raw = await self._ask_llm(prompt, max_tokens=300)
            return Agent1Output.model_validate_json(raw)
        except Exception:
            return heuristic_agent1(text)

    async def _agent2_find(self, text: str, language: str, jurisdiction: str) -> Agent2Output:
        if self.client is None:
            return heuristic_agent2(text)

        prompt = f"""
You are Agent 2.
You receive language and jurisdiction, and must find vague/ambiguous contract sentences.
Return ONLY JSON with this schema:
{{
  "findings": [
    {{
      "sentence": "exact sentence from document",
      "issue": "why it is vague/ambiguous",
      "suggestion": "clear rewrite suggestion",
      "severity": "high|medium|low"
    }}
  ],
  "summary": "short summary"
}}
Limit findings to {settings.max_findings}.

Language: {language}
Jurisdiction: {jurisdiction}
Document:
\"\"\"{text[:24000]}\"\"\"
"""
        try:
            raw = await self._ask_llm(prompt, max_tokens=2000)
            payload = Agent2Output.model_validate_json(raw)
            cleaned = [normalize_finding(item) for item in payload.findings]
            return Agent2Output(findings=cleaned, summary=payload.summary)
        except Exception:
            return heuristic_agent2(text)

    async def _ask_llm(self, prompt: str, *, max_tokens: int) -> str:
        if self.client is None:
            raise RuntimeError("No OpenAI client configured")

        response = await self.client.responses.create(
            model=settings.openai_model,
            max_output_tokens=max_tokens,
            temperature=0,
            input=prompt,
        )
        response_text = getattr(response, "output_text", "")
        if not response_text:
            raise ValueError("Empty response from OpenAI")
        return extract_json_text(response_text)


def split_sentences(text: str) -> list[SentenceItem]:
    chunks = re.split(r"(?<=[.!?])\s+|\n+", text)
    output: list[SentenceItem] = []
    for i, sentence in enumerate(chunks, start=1):
        clean = sentence.strip()
        if clean:
            output.append(SentenceItem(text=clean, position=i))
    return output


def normalize_finding(finding: Finding) -> Finding:
    sev = finding.severity.lower().strip()
    if sev not in {"high", "medium", "low"}:
        sev = "medium"
    return Finding(
        sentence=finding.sentence.strip(),
        issue=finding.issue.strip(),
        suggestion=finding.suggestion.strip(),
        severity=sev,
    )


def extract_json_text(raw_text: str) -> str:
    fenced = re.search(r"```(?:json)?\s*(\{.*\})\s*```", raw_text, flags=re.S)
    if fenced:
        return fenced.group(1)
    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Could not locate JSON in model response")
    return raw_text[start : end + 1]


def heuristic_agent1(text: str) -> Agent1Output:
    lowered = text.lower()
    language = "English"
    if any(token in lowered for token in (" clá", " contrato", " deverá", " fica estabelecido")):
        language = "Portuguese"
    elif any(token in lowered for token in (" contrato", " deberá", " queda establecido")):
        language = "Spanish"

    jurisdiction = "Unknown"
    rules: list[tuple[str, str]] = [
        (r"laws? of (the )?united states|state of [a-z]+", "United States"),
        (r"laws? of brazil|leis? brasileiras?|c[oó]digo civil brasileiro", "Brazil"),
        (r"laws? of england and wales", "England and Wales"),
    ]
    for pattern, name in rules:
        if re.search(pattern, lowered):
            jurisdiction = name
            break
    return Agent1Output(language=language, jurisdiction=jurisdiction)


def heuristic_agent2(text: str) -> Agent2Output:
    ambiguous_terms = (
        "reasonable",
        "as soon as possible",
        "promptly",
        "best efforts",
        "if necessary",
        "material",
        "adequate",
        "from time to time",
    )
    findings: list[Finding] = []
    for sentence in split_sentences(text):
        lowered = sentence.text.lower()
        for term in ambiguous_terms:
            if term in lowered:
                findings.append(
                    Finding(
                        sentence=sentence.text,
                        issue=f"Contains subjective term '{term}' without objective criteria.",
                        suggestion=(
                            "Replace with measurable obligations, exact deadlines, and clear acceptance criteria."
                        ),
                        severity="medium",
                    )
                )
                break

    if findings:
        summary = "Potentially vague or ambiguous clauses were identified."
    else:
        summary = "No obvious vague clauses found by fallback heuristic."
    return Agent2Output(findings=findings[: settings.max_findings], summary=summary)
