from __future__ import annotations

import json
import time
from typing import Any, Dict, List, Tuple


def as_int(value: Any, default: int = 0) -> int:
    try:
        if value is None or value is False:
            return default
        return int(float(value))
    except (TypeError, ValueError):
        return default


def as_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def maybe_json(value: Any) -> Any:
    if isinstance(value, (dict, list)) or value in (None, ""):
        return value
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    return value


class TTLCache:
    def __init__(self) -> None:
        self._store: Dict[str, Tuple[float, Any]] = {}

    def get(self, key: str) -> Any:
        item = self._store.get(key)
        if not item:
            return None
        expires, value = item
        if expires < time.time():
            return None
        return value

    def set(self, key: str, value: Any, ttl: float) -> None:
        self._store[key] = (time.time() + ttl, value)

    def delete(self, key: str) -> None:
        self._store.pop(key, None)


def downsample(points: List[dict], max_points: int) -> List[dict]:
    if len(points) <= max_points or max_points <= 0:
        return points
    step = len(points) / max_points
    out = []
    i = 0.0
    while i < len(points):
        out.append(points[int(i)])
        i += step
    if out[-1] is not points[-1]:
        out.append(points[-1])
    return out
