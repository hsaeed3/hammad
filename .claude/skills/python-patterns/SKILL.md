---
name: "python-patterns"
description: "Pythonic idioms, PEP 8 standards, type hints, and best practices for building robust, efficient, and maintainable Python applications; as well as best practices for associated tooling. Use this skill when writing or reviewing Python code and idiomatic structure."
license: MIT
metadata:
    tags: "Python, PEP 8, Type Hints, Best Practices"
---

# python-patterns

Idiomatic Python plus the toolchain that is actually current. Two halves:

1. **Tooling** — what to reach for, what it replaced, and the exact commands.
   Read this first; getting it wrong produces a project that looks like 2021.
2. **Language patterns** — idioms, typing, error handling, performance.

## When to Activate

- Writing, reviewing, or refactoring Python code
- Creating or editing a `pyproject.toml`
- Adding, removing, or locking dependencies
- Configuring linting, formatting, type checking, or git hooks
- Setting up CI, building, or publishing a package
- Designing Python packages/modules

---

# Part 1: Modern Tooling

## The replacement table (read before touching any config)

Never reach for the left column. If existing code uses it, note it and offer
migration — don't silently keep using it, and don't introduce it into a new
project under any circumstance.

| Do NOT use | Use instead | Notes |
|---|---|---|
| `pip`, `pip-tools` | `uv add` / `uv sync` / `uv lock` | uv resolves and locks |
| `poetry`, `pdm`, `pipenv` | `uv` | full project manager |
| `venv`, `virtualenv` | `uv venv` (usually implicit) | `uv run` manages it |
| `pyenv` | `uv python install` / `.python-version` | uv manages interpreters |
| `pipx` | `uvx` / `uv tool run` | ephemeral tool execution |
| `setuptools`, `hatchling`, `flit` (as backend) | `uv_build` | unless a reason exists |
| `black` | `ruff format` | |
| `isort` | `ruff check --select I --fix` | ruff sorts imports |
| `flake8`, `pylint`, `pyupgrade`, `bandit` | `ruff check` | one linter, rule families |
| `mypy`, `pyright` | `ty` | Astral's checker |
| `pre-commit` | `prek` | same config file |
| `requirements.txt` | `pyproject.toml` + `uv.lock` | export only if forced |

Two exceptions worth knowing rather than fighting:

- **`hatchling` is still correct** when the package needs build-time hooks
  `uv_build` doesn't support (compiled extensions, custom build steps,
  version-from-VCS plugins). `uv_build` is the default, not the only option.
- **`mypy`/`pyright` are still correct** when a project already has a large
  mypy-clean codebase or depends on plugin ecosystems ty doesn't have yet.
  ty is not a drop-in replacement — it makes different design choices, checks
  unannotated function bodies mypy skips, and a mypy-clean codebase can
  surface many new errors on first `ty check`. For new projects, use ty.

## uv

uv is the package manager, project manager, interpreter manager, lockfile
tool, script runner, build frontend, and publisher. One binary.

### Project layout

```
myproject/
├── .python-version          # pinned interpreter (uv manages it)
├── .pre-commit-config.yaml  # read by prek
├── pyproject.toml
├── uv.lock                  # COMMIT THIS
├── README.md
├── src/
│   └── mypackage/
│       ├── __init__.py
│       ├── py.typed         # ship this if the package is typed
│       └── models.py
└── tests/
    ├── conftest.py
    └── test_models.py
```

`src/` layout is the default for a reason — it prevents accidentally
importing the working-tree copy instead of the installed package, which is
exactly the bug that makes "works locally, broken on PyPI" happen.

### pyproject.toml — full modern reference

```toml
[project]
name = "mypackage"
version = "0.1.0"
description = "A sample Python package."
readme = "README.md"
authors = [{ name = "Your Name", email = "you@example.com" }]
requires-python = ">=3.12"
dependencies = [
    "httpx>=0.28",
    "pydantic>=2.0",
]

[project.scripts]
mypackage = "mypackage:main"

# PEP 735 dependency groups. NEVER published, never installed by consumers.
# This is where dev tooling goes — not in [project.optional-dependencies].
[dependency-groups]
dev = [
    "ruff>=0.15",
    "ty>=0.0.1a1",
    "prek>=0.2",
]
test = [
    "pytest>=8.0",
    "pytest-cov>=6.0",
]
docs = ["mkdocs-material>=9.0"]

[build-system]
requires = ["uv_build>=0.12.5,<0.13"]
build-backend = "uv_build"

[tool.uv]
# `dev` is synced by default; add others here to avoid --group on every call.
default-groups = ["dev", "test"]

[tool.ruff]
line-length = 88
# target-version is inferred from project.requires-python — only set it to
# override.

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # Pyflakes
    "I",    # isort (import sorting)
    "UP",   # pyupgrade (modernize syntax for the target version)
    "B",    # flake8-bugbear (real bug patterns)
    "C4",   # flake8-comprehensions
    "SIM",  # flake8-simplify
    "TC",   # flake8-type-checking
    "RUF",  # ruff-specific rules
]
ignore = ["E501"]  # line length is the formatter's job, not the linter's

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false

[tool.ty.rules]
possibly-missing-import = "error"
unused-ignore-comment = "warn"

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=mypackage --cov-report=term-missing"
```

Notes on the above that are easy to get wrong:

- **`[dependency-groups]` is not `[project.optional-dependencies]`.** Groups
  are dev-only and never reach PyPI. Optional-dependencies are *extras* users
  can install (`pip install mypackage[cli]`). Dev tooling in extras is a
  packaging bug — it makes every consumer's resolver consider your linter.
- **`select` vs `extend-select`**: `select` *replaces* the default rule set,
  `extend-select` adds to it. Prefer explicit `select` so the rule set is
  fully visible in the file. Using `select` and forgetting `F` silently drops
  unused-import and undefined-name checks.
- **`ALL` is available but discouraged** — it implicitly enables new rules on
  every ruff upgrade, so upgrades break CI for unrelated reasons.
- **Pin the `uv_build` upper bound.** The backend follows uv's versioning;
  an unbounded requirement means a future uv can change build behavior.

### uv commands

```bash
# Project creation
uv init myproject               # packaged src/ layout + uv_build (default)
uv init myproject --lib         # library
uv init myproject --no-package  # flat, unpackaged script project
uv init myproject --bare        # minimal pyproject, no scaffold

# Dependencies
uv add httpx                    # runtime dependency
uv add "flask>=3.0,<4"
uv add --dev pytest             # -> [dependency-groups] dev
uv add --group test pytest-cov  # -> [dependency-groups] test
uv remove httpx
uv lock                         # resolve -> uv.lock
uv lock --upgrade-package httpx # bump one package
uv tree                         # dependency tree

# Environment
uv sync                         # project deps + default groups
uv sync --group docs
uv sync --only-group test       # ONLY that group (fast CI jobs)
uv sync --all-groups
uv sync --no-dev                # production
uv sync --locked                # fail if lockfile is stale (USE IN CI)
uv sync --frozen                # use lockfile as-is, don't re-resolve

# Running
uv run pytest                   # auto-syncs first
uv run python -m mypackage
uv run --with rich script.py    # temporary extra dependency

# Interpreters
uv python install 3.13
uv python pin 3.13              # writes .python-version

# Tools (pipx replacement)
uvx ruff check .                # ephemeral, nothing installed
uv tool install ruff            # persistent
uv tool run ruff check .        # same as uvx

# Scripts (PEP 723 inline metadata)
uv init --script analyze.py
uv add --script analyze.py httpx pandas
uv run analyze.py               # deps resolved from the script header

# Build & publish
uv version --bump minor
uv build                        # sdist + wheel into dist/
uv publish
uv export --format requirements-txt  # only when a consumer demands it
```

`uv run` verifies the lockfile matches `pyproject.toml` and the environment
matches the lockfile before every invocation — so a stale env is not a
failure mode you need to think about. In CI, use `--locked` so a
lockfile someone forgot to commit fails the build instead of being silently
regenerated.

### PEP 723 scripts

For a standalone script, don't create a project — inline the metadata:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///

import httpx
import rich

rich.print(httpx.get("https://example.com").status_code)
```

Run with `uv run script.py`. uv builds a throwaway environment. This is the
correct answer to "how do I share a Python script that has dependencies."

## ruff

One tool for linting and formatting. Two separate commands — the formatter
does **not** sort imports, so lint-fix first, then format.

```bash
ruff check .                # lint
ruff check --fix .          # lint + autofix (includes import sorting)
ruff check --watch .
ruff format .               # format
ruff format --check .       # verify only — use in CI
ruff rule F401              # explain a rule
```

Correct order, always:

```bash
uv run ruff check --fix .
uv run ruff format .
```

Suppress narrowly, never broadly:

```python
import os  # noqa: F401  — good: names the rule

import os  # noqa        — bad: blanket suppression
```

## ty

Astral's type checker. Config lives in `[tool.ty]` in `pyproject.toml`, or a
`ty.toml` (which takes precedence if both exist).

```bash
ty check                    # check the project
ty check src/               # check a path
ty check --error all        # promote every rule to error
ty check --exit-zero        # report but don't fail
```

Rules are set to `error`, `warn`, or `ignore` — either on the CLI
(`--error possibly-missing-import`) or in config:

```toml
[tool.ty.rules]
index-out-of-bounds = "ignore"
possibly-missing-attribute = "error"
```

Suppression is per-rule, so unrelated checks stay live on that line:

```python
value = obj.attr  # ty: ignore[possibly-missing-attribute]
```

ty respects `# type: ignore` by default; disable that with
`respect-type-ignore-comments = false` under `[tool.ty.analysis]` if you want
to force the explicit `ty: ignore` form.

Two behavioral notes that surprise people migrating from mypy: ty checks
unannotated function bodies (mypy skips them), and it offers a *gradual
guarantee* — adding annotations to working code should never introduce new
errors.

## prek

Git hook manager, drop-in replacement for pre-commit. **Same
`.pre-commit-config.yaml`, unchanged** — the only migration is swapping the
command name. It's a single Rust binary with no runtime dependency, uses uv
for hook environments, and runs hooks in parallel.

```bash
prek install                # install git hooks
prek install -f             # also shim the `pre-commit` binary
prek run --all-files
prek run --hook-stage pre-push --all-files
prek autoupdate
prek clean
```

```yaml
# .pre-commit-config.yaml
default_install_hook_types: [pre-commit, pre-push]

repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.0
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format

  - repo: local
    hooks:
      - id: ty
        name: ty
        entry: uv run --isolated ty check
        language: system
        pass_filenames: false
```

The `ty` hook runs through `uv run` so project dependencies resolve during
the check, `--isolated` keeps it from mutating the lockfile or venv, and
`pass_filenames: false` runs it across the whole project — a type change in
one module breaks another module that wasn't staged.

## CI (GitHub Actions)

```yaml
name: CI
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true
      - run: uv sync --locked --all-groups
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run ty check
      - run: uv run pytest
```

`--locked` is the important flag: it fails if `uv.lock` is out of sync with
`pyproject.toml`, which catches the "worked on my machine because my lockfile
was newer" class of bug at PR time.

---

# Part 2: Language Patterns

## Core Principles

### Readability counts

```python
# Good
def get_active_users(users: list[User]) -> list[User]:
    """Return only active users from the provided list."""
    return [user for user in users if user.is_active]

# Bad — clever, unreadable, untyped
def get_active_users(u):
    return [x for x in u if x.a]
```

### Explicit over implicit

```python
# Good
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

# Bad — what did this do?
import some_module
some_module.setup()
```

### EAFP over LBYL

```python
# Good — one lookup, no race between check and use
def get_value(mapping: dict[str, Any], key: str, default: Any = None) -> Any:
    try:
        return mapping[key]
    except KeyError:
        return default

# Bad — two lookups, and the LBYL pattern breaks under concurrency
def get_value(mapping: dict[str, Any], key: str, default: Any = None) -> Any:
    if key in mapping:
        return mapping[key]
    return default
```

## Type Hints

### Use modern syntax

`typing.List`, `typing.Dict`, `typing.Optional`, and `typing.Union` are
legacy. Built-in generics and `|` unions are correct on every supported
Python version. Ruff's `UP` rules will flag the old forms.

```python
# Good
def process(items: list[str], meta: dict[str, Any]) -> User | None: ...

# Bad — legacy typing imports
from typing import List, Dict, Optional
def process(items: List[str], meta: Dict[str, Any]) -> Optional[User]: ...
```

### Type aliases

```python
from typing import TypeAlias

JSON: TypeAlias = dict[str, "JSON"] | list["JSON"] | str | int | float | bool | None
"""Any JSON-representable value."""

def parse_json(data: str) -> JSON:
    return json.loads(data)
```

On Python 3.12+, prefer the `type` statement:

```python
type JSON = dict[str, JSON] | list[JSON] | str | int | float | bool | None
```

### Generics (3.12+ syntax)

```python
# Good — PEP 695, no TypeVar boilerplate
def first[T](items: list[T]) -> T | None:
    """Return the first item, or None if empty."""
    return items[0] if items else None

# Pre-3.12
from typing import TypeVar
T = TypeVar("T")
def first(items: list[T]) -> T | None:
    return items[0] if items else None
```

### Protocol-based duck typing

```python
from typing import Protocol

class Renderable(Protocol):
    def render(self) -> str: ...

def render_all(items: list[Renderable]) -> str:
    """Render every item implementing the Renderable protocol."""
    return "\n".join(item.render() for item in items)
```

Protocols beat ABCs when you don't control the implementing classes — no
inheritance required, structural matching only.

## Error Handling

### Catch specific exceptions, chain the cause

```python
# Good
def load_config(path: Path) -> Config:
    try:
        return Config.from_json(path.read_text())
    except FileNotFoundError as e:
        raise ConfigError(f"Config file not found: {path}") from e
    except json.JSONDecodeError as e:
        raise ConfigError(f"Invalid JSON in config: {path}") from e

# Bad — swallows everything, returns None, loses the traceback
def load_config(path: Path) -> Config:
    try:
        return Config.from_json(path.read_text())
    except:
        return None
```

`from e` preserves the original traceback. `from None` deliberately hides it
— correct only when the internal cause would confuse the caller (see the
public-error-boundary pattern).

### Exception hierarchy

Give the package one base exception so callers can catch everything from
your library with a single `except`:

```python
class AppError(Exception):
    """Base exception for all application errors."""

class ValidationError(AppError):
    """Raised when input validation fails."""

class NotFoundError(AppError):
    """Raised when a requested resource is not found."""
```

### ExceptionGroup (3.11+)

```python
async def fetch_all(urls: list[str]) -> list[str]:
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch(url)) for url in urls]
    return [t.result() for t in tasks]

try:
    results = await fetch_all(urls)
except* httpx.TimeoutException as eg:
    logger.warning("%d requests timed out", len(eg.exceptions))
except* httpx.HTTPStatusError as eg:
    logger.error("%d requests failed", len(eg.exceptions))
```

## Context Managers

```python
# Good
def process_file(path: Path) -> str:
    with path.open() as f:
        return f.read()

# Custom, via decorator
from contextlib import contextmanager

@contextmanager
def timer(name: str) -> Iterator[None]:
    """Time the enclosed block."""
    start = time.perf_counter()
    try:
        yield
    finally:
        elapsed = time.perf_counter() - start
        print(f"{name} took {elapsed:.4f}s")
```

The `try/finally` around the `yield` matters — without it, an exception in
the body skips the cleanup entirely.

```python
# Class-based, when state is involved
class DatabaseTransaction:
    def __init__(self, connection: Connection) -> None:
        self.connection = connection

    def __enter__(self) -> "DatabaseTransaction":
        self.connection.begin_transaction()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        if exc_type is None:
            self.connection.commit()
        else:
            self.connection.rollback()
        return False  # never suppress
```

## Comprehensions and Generators

```python
# Good — simple transformation
names = [user.name for user in users if user.is_active]

# Bad — too much logic crammed in
result = [transform(x) for x in items if x > 0 if x % 2 == 0 if validate(x)]

# Good — expand it
def filter_and_transform(items: Iterable[int]) -> list[int]:
    result = []
    for x in items:
        if x > 0 and x % 2 == 0 and validate(x):
            result.append(transform(x))
    return result
```

```python
# Good — generator expression, no intermediate list
total = sum(x * x for x in range(1_000_000))

# Bad — materializes a million-element list to throw it away
total = sum([x * x for x in range(1_000_000)])
```

```python
# Good — lazy line-by-line
def read_lines(path: Path) -> Iterator[str]:
    """Yield stripped lines from a file."""
    with path.open() as f:
        for line in f:
            yield line.strip()
```

## Data Containers

```python
from dataclasses import dataclass, field
from datetime import UTC, datetime

@dataclass(slots=True, frozen=True)
class User:
    """User entity with generated __init__, __repr__, and __eq__."""
    id: str
    name: str
    email: str
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    is_active: bool = True
```

`slots=True` (3.10+) gets the `__slots__` memory win with no boilerplate.
`frozen=True` makes it hashable and prevents accidental mutation — default
to it unless you specifically need mutability. `datetime.now(UTC)` rather
than `datetime.now()`, which is naive and will bite you across timezones.

```python
# Validation in __post_init__
@dataclass
class Account:
    email: str
    age: int

    def __post_init__(self) -> None:
        if "@" not in self.email:
            raise ValidationError(f"Invalid email: {self.email}")
        if not 0 <= self.age <= 150:
            raise ValidationError(f"Invalid age: {self.age}")
```

Choosing a container:

| Need | Use |
|---|---|
| Plain data, internal | `@dataclass(slots=True)` |
| Immutable value object | `@dataclass(frozen=True, slots=True)` |
| Tuple-like, unpackable | `NamedTuple` |
| Parsing/validating untrusted input | `pydantic.BaseModel` |
| Typed dict from JSON | `TypedDict` |

Reach for pydantic at trust boundaries (API payloads, config files, LLM
output) — not for internal structs, where a dataclass is faster and has no
dependency cost.

## Decorators

```python
import functools

def timer[**P, R](func: Callable[P, R]) -> Callable[P, R]:
    """Time function execution."""
    @functools.wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        start = time.perf_counter()
        result = func(*args, **kwargs)
        print(f"{func.__name__} took {time.perf_counter() - start:.4f}s")
        return result
    return wrapper
```

`functools.wraps` is not optional — without it the wrapped function loses
its `__name__`, `__doc__`, and signature, which breaks introspection, docs
tooling, and debuggers.

```python
# Parameterized
def repeat(times: int):
    """Repeat the decorated function `times` times, collecting results."""
    def decorator[**P, R](func: Callable[P, R]) -> Callable[P, list[R]]:
        @functools.wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> list[R]:
            return [func(*args, **kwargs) for _ in range(times)]
        return wrapper
    return decorator
```

## Concurrency

Pick by workload, not by preference:

| Workload | Tool |
|---|---|
| I/O-bound, async-native libs | `asyncio` + `TaskGroup` |
| I/O-bound, blocking libs | `ThreadPoolExecutor` |
| CPU-bound | `ProcessPoolExecutor` |

```python
# Async I/O — TaskGroup (3.11+) over bare gather: structured, cancels siblings
async def fetch_all(urls: list[str]) -> list[str]:
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch_async(url)) for url in urls]
    return [t.result() for t in tasks]

# Blocking I/O in threads
def fetch_all_urls(urls: list[str]) -> dict[str, str]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(fetch_url, u): u for u in urls}
        results = {}
        for future in concurrent.futures.as_completed(futures):
            url = futures[future]
            try:
                results[url] = future.result()
            except Exception as e:
                results[url] = f"Error: {e}"
    return results

# CPU-bound in processes
def process_all(datasets: list[list[int]]) -> list[int]:
    with concurrent.futures.ProcessPoolExecutor() as executor:
        return list(executor.map(process_data, datasets))
```

## Package Exports

```python
# src/mypackage/__init__.py
"""mypackage - A sample Python package."""

from mypackage.models import Post, User
from mypackage.utils import format_name

__all__ = ["Post", "User", "format_name"]
```

`__all__` is the public API contract — it controls `from mypackage import *`,
signals intent to linters, and is the first thing to check when deciding
whether a symbol is public. Ship `py.typed` (an empty marker file) in the
package directory or consumers won't see your annotations.

## Performance

```python
# Bad — O(n²), rebuilds the string every iteration
result = ""
for item in items:
    result += str(item)

# Good — O(n)
result = "".join(str(item) for item in items)
```

```python
# Bad — loads the whole file into memory
def read_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.open()]

# Good — constant memory
def read_lines(path: Path) -> Iterator[str]:
    with path.open() as f:
        for line in f:
            yield line.strip()
```

```python
# Memory-efficient classes: prefer slots=True on the dataclass decorator
@dataclass(slots=True)
class Point:
    x: float
    y: float
```

Measure before optimizing. `time.perf_counter()` for wall-clock,
`timeit` for micro-benchmarks, `cProfile` + `snakeviz` for hot-path hunting.

## Quick Reference: Idioms

| Idiom | Description |
|---|---|
| EAFP | Try it, catch the failure — don't pre-check |
| `pathlib.Path` | Never `os.path` string juggling |
| f-strings | Never `%` or `.format()` |
| `X \| None` | Never `Optional[X]` |
| `list[str]` | Never `typing.List[str]` |
| `@dataclass(slots=True)` | Data containers |
| Generators | Lazy evaluation, large data |
| `enumerate` / `zip` | Never manual index arithmetic |
| `TaskGroup` | Structured async concurrency |
| `datetime.now(UTC)` | Never naive datetimes |
| Context managers | Any resource with cleanup |

## Anti-Patterns to Avoid

```python
# Bad: Mutable default arguments
def append_to(item, items=[]):
    items.append(item)
    return items

# Good: Use None and create new list
def append_to(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items

# Bad: Checking type with type()
if type(obj) == list:
    process(obj)

# Good: Use isinstance
if isinstance(obj, list):
    process(obj)

# Bad: Comparing to None with ==
if value == None:
    process()

# Good: Use is
if value is None:
    process()

# Bad: from module import *
from os.path import *

# Good: Explicit imports
from os.path import join, exists

# Bad: Bare except
try:
    risky_operation()
except:
    pass

# Good: Specific exception
try:
    risky_operation()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
```

Two more that the modern toolchain makes newly relevant:

```python
# Bad: mutable class attribute shared across every instance
class Config:
    items = []          # every Config() shares this list

# Good
@dataclass
class Config:
    items: list[str] = field(default_factory=list)
```

```python
# Bad: pinning exact versions in a library's dependencies
dependencies = ["httpx==0.28.1"]   # forces conflicts on every consumer

# Good: lower bounds in the library, exact versions in uv.lock
dependencies = ["httpx>=0.28"]
```

The second one is the single most common packaging mistake: `uv.lock`
already gives you reproducibility for *applications*. Pinning exact versions
in a *library's* `dependencies` just makes your package uninstallable
alongside anything else.

---

__Remember__: Python code should be readable, explicit, and follow the
principle of least surprise. When in doubt, prioritize clarity over
cleverness — and check that the tool you're about to reach for hasn't been
replaced.