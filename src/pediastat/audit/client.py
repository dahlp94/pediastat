"""Minimal GDC HTTP client.

Requests use explicit timeouts and do not retry. Controlled-access downloads
are refused.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import requests

from pediastat.audit.constants import DEFAULT_TIMEOUT_SECONDS, GDC_API_BASE_URL


class GDCAPIError(Exception):
    """Raised when a GDC API request fails."""

    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class GDCClient:
    """Thin wrapper around the official GDC search-and-retrieval API."""

    def __init__(
        self,
        base_url: str = GDC_API_BASE_URL,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        session: requests.Session | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.session = session or requests.Session()
        self.session.headers.setdefault(
            "User-Agent", "PediaStat-source-audit (TARGET-AML; no controlled-access)"
        )

    def _url(self, path: str) -> str:
        return f"{self.base_url}/{path.lstrip('/')}"

    def _raise_for_status(self, response: requests.Response, url: str) -> None:
        if response.status_code >= 400:
            detail = (response.text or "").strip().replace("\n", " ")
            if len(detail) > 300:
                detail = detail[:300] + "..."
            msg = f"GDC request failed ({response.status_code}) for {url}"
            if detail:
                msg = f"{msg}: {detail}"
            raise GDCAPIError(msg, status_code=response.status_code)

    def get_json(self, path: str, params: dict[str, Any] | None = None) -> Any:
        url = self._url(path)
        try:
            response = self.session.get(
                url, params=params, timeout=self.timeout_seconds
            )
        except requests.RequestException as exc:
            raise GDCAPIError(f"GDC GET {url} failed: {exc}") from exc
        self._raise_for_status(response, url)
        try:
            return response.json()
        except ValueError as exc:
            raise GDCAPIError(f"GDC GET {url} returned non-JSON") from exc

    def post_json(self, path: str, payload: dict[str, Any]) -> Any:
        url = self._url(path)
        try:
            response = self.session.post(
                url,
                json=payload,
                timeout=self.timeout_seconds,
            )
        except requests.RequestException as exc:
            raise GDCAPIError(f"GDC POST {url} failed: {exc}") from exc
        self._raise_for_status(response, url)
        try:
            return response.json()
        except ValueError as exc:
            raise GDCAPIError(f"GDC POST {url} returned non-JSON") from exc

    def download_open_file(self, file_id: str, destination: Path) -> None:
        """Download one open-access GDC file. Refuses to guess at tokens."""
        url = self._url(f"data/{file_id}")
        try:
            response = self.session.get(url, timeout=self.timeout_seconds, stream=True)
        except requests.RequestException as exc:
            raise GDCAPIError(f"GDC download {url} failed: {exc}") from exc
        if response.status_code in {401, 403}:
            raise GDCAPIError(
                f"Refusing controlled or unauthorized GDC download for {file_id}",
                status_code=response.status_code,
            )
        self._raise_for_status(response, url)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 64):
                if chunk:
                    handle.write(chunk)
