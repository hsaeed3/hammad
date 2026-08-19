---
name: "python-sdk-ergonomics"
description: "Opinionated ruleset and guide that applies to an SDK or package-focused Python project. Provides practices for both the user-focused surface and internal architecture."
license: MIT
metadata:
    tags: "Python, SDK, Code Styling, Best Practices"
---

# python-sdk-ergonomics

Code has two audiences: the maintainer who has to modify it, and the user who
has to call it without reading its source. These audiences want opposite
things. A public API optimizes for the caller who knows nothing about the
internals — clarity, discoverability, forgiving defaults. Internal code
optimizes for the maintainer who knows everything about the internals —
speed of reading, proximity to the problem, zero ceremony.

Applying user-facing polish to internal code is wasted effort that slows
down maintenance. Applying internal-code bluntness to a public surface is
what makes libraries frustrating to use. The first job, every time, is
figuring out which one you're looking at.

## Step 0: Classify the surface (always, before any rule below)

Ask, in order, stopping at the first match:

1. **Is it exported?** Check `__init__.py` and `__all__`. If the name is
   re-exported at the package's top level or a documented subpackage level,
   it's **public**, full stop — regardless of how it's implemented.
2. **Does the name start with `_`?** A leading underscore (module, class,
   function, or attribute) is **internal**, full stop — this is a hard
   signal, never softened by "but it's used a lot internally."
3. **What directory is it in?** Paths like `_internal/`, `internals/`,
   `core/_impl.py`, `*/private/*` are **internal** by convention even if a
   given symbol inside isn't underscore-prefixed yet (flag this as a gap,
   don't silently treat it as public).
4. **Does it appear in documentation, README examples, or the docs site?**
   If a user is shown this symbol as something to call, it's **public**
   even if it technically isn't in `__all__` yet (flag that omission).
5. **Still ambiguous?** Default to treating it as **internal** — the cost
   of under-polishing something a user never sees is zero; the cost of
   over-committing to a public contract you didn't mean to make is real
   (once it's out, it's a breaking change to fix). State the assumption
   out loud and move on; don't stall on this.

This classification isn't a one-time file-level judgment — a single module
routinely contains both. A public `Grid` class can have a private
`_reconcile_diff()` method three lines below it. Classify per-symbol, not
per-file.

```python
# grid.py

class Grid:                       # public — exported in __all__
    def render(self) -> str: ...  # public — this is the point of the class

    def _reconcile_diff(self, prev: "Grid") -> list[Diff]:  # internal
        ...                                                  # leading _,
                                                               # never shown
                                                               # to a user
```

## Public surfaces (user-facing)

### Naming
- Names describe *what the user gets or causes*, never *how it's
  implemented internally*.
- One concept, one name, everywhere. If `timeout` means "seconds until
  cancel" in one function, it means that in all of them — no `timeout` here
  and `max_wait` there for the same idea.
- No abbreviations a newcomer to the library would have to learn, same
  standard as internal code, but the stakes are higher here since users
  can't grep the source to disambiguate.

```python
# Bad — describes the implementation, not the outcome
def flush_buffer_to_terminal(self) -> None: ...

# Good — describes what the caller gets
def render(self) -> str: ...

# Bad — same concept, two names, forces the user to memorize both
def connect(self, timeout: float = 5.0): ...
def request(self, max_wait: float = 5.0): ...

# Good — one name for one concept, everywhere
def connect(self, timeout: float = 5.0): ...
def request(self, timeout: float = 5.0): ...
```

### Signatures
- The common case must be callable with the fewest arguments possible.
  If 80% of calls pass the same three kwargs, those three either get
  sensible defaults or the API is wrong.
- No boolean traps. A bare positional `bool` is a landmine at every call
  site — keyword-only, or an enum/Literal when a real third option is
  waiting to happen.
- Every public parameter and return type is fully type-hinted. No `Any`
  leaking into a public signature unless the function is genuinely generic
  by design.
- Return types are boring and consistent — pick one failure pattern
  (raise, or a `Result` type, or a sentinel) and use it everywhere on the
  public surface, never a mix.

```python
# Bad — common case forces the user to know and pass internal detail
def run(agent, model, provider, max_tokens, temperature): ...
run(my_agent, "gpt-4", "openai", 1024, 0.7)

# Good — common case just works, everything else is opt-in
def run(agent, *, model: str = "gpt-4", **overrides): ...
run(my_agent)

# Bad — boolean trap, unreadable at the call site
def fetch(url, True): ...

# Good — keyword-only, self-documenting at the call site
def fetch(url, *, strict: bool = False): ...
fetch(url, strict=True)

# Bad — inconsistent, undocumented failure contract
def parse(text) -> dict | None | ValueError: ...

# Good — one contract, used everywhere on the public surface
def parse(text) -> dict:
    """Raises ParseError on failure."""
```

### Errors
- A public-facing error names the failure in terms the caller can act on,
  not in terms of what broke internally.
- Internal exceptions get caught and re-raised as public ones at the
  boundary — a user should never see a traceback whose top frame is a
  private module they can't inspect without reading your source.

```python
# Bad — leaks an internal implementation detail as the public contract
def load_config():
    return _raw_dict["api_key"]  # raises bare KeyError: 'api_key'

# Good — caught at the boundary, re-raised in terms the user can act on
def load_config():
    try:
        return _raw_dict["api_key"]
    except KeyError:
        raise ConfigMissingError(
            '"API_KEY" not set — check your .env has API_KEY set.'
        ) from None
```

### Discoverability
- Prefer flat imports at the top level for anything genuinely public over
  forcing users to know internal module paths. Deep import paths are for
  internal code and opt-in advanced usage, not the default experience.
- Docstrings on every public symbol are mandatory, `Args:`/`Returns:`/
  `Raises:`, written for someone who has never opened this file — a
  docstring that just restates the type hint isn't doing its job.

```python
# Bad — user has to know the internal module layout to call the library
from zyx.core.agents.execution.loop import run_agent_loop
run_agent_loop(agent)

# Good — flat, discoverable top-level surface
import zyx
zyx.run(agent)

# Bad — docstring restates the signature, tells the reader nothing new
def run(agent: Agent, model: str) -> Result:
    """Runs the agent with a model.

    Args:
        agent: An agent.
        model: A model.
    """

# Good — written for someone who's never seen this file
def run(agent: Agent, model: str = "gpt-4") -> Result:
    """Run agent to completion against the given model.

    Args:
        agent: The agent to execute. Must already be configured with tools.
        model: Model identifier to use for generation. Defaults to "gpt-4".

    Returns:
        The final Result once the agent loop terminates.

    Raises:
        AgentTimeoutError: If the loop exceeds the agent's configured
            timeout without terminating.
    """
```

### Stability
- Once something is public, changing its signature is a breaking change —
  treat this as real friction before adding a parameter, not an
  afterthought. If you're not sure a new parameter should be permanent,
  it probably shouldn't be on the public symbol yet.

```python
# Bad — silently changes the public contract for every existing caller
# v1.0: def run(agent, model="gpt-4")
# v1.1: def run(agent, model="gpt-4", strategy="cot")  # existing callers
#                                                        # now behave
#                                                        # differently
#                                                        # with no signal

# Good — new behavior opt-in, existing callers unaffected
def run(agent, model="gpt-4", *, strategy: str | None = None):
    strategy = strategy or agent.default_strategy
```

## Internal surfaces (maintainer-facing)

- Optimize for the person reading this in six months with full context of
  the surrounding module — proximity and terseness over spelled-out clarity.
  Short names are fine if the scope is small and the meaning is obvious
  from context; the abbreviation ban is a public-API rule, not universal.
- Docstrings are optional and should exist only where behavior isn't
  obvious from the code itself.
- No obligation toward stable signatures — change internal function
  signatures freely as the implementation evolves.
- Type hints still required (baseline project convention, not an
  ergonomics concern) but can be looser — `Any`, internal-only types, and
  partial coverage are acceptable here in ways they aren't on public
  surfaces.
- Errors can be blunt and implementation-specific.

```python
# Fine for internal code — small scope, obvious from context,
# no docstring needed, terse names are not a violation here
def _diff(a: list[int], b: list[int]) -> list[int]:
    return [x for x in b if x not in a]

# Also fine — internal signature changes freely, no stability obligation
def _reconcile(prev, curr, *, fast=True):  # `fast` added last week,
    ...                                     # renamed next week, no
                                             # deprecation cycle needed
```

## When editing existing code that crosses the boundary

If a change touches both a public function and the internal helper it
calls, apply each surface's rules to itself — don't let the internal
helper's bluntness leak upward into the public signature, and don't let
the public function's polish obligations bleed downward into demanding
docstrings on every internal helper it happens to call.

```python
# Good — public/internal boundary respected in one edit
def run(agent: Agent, model: str = "gpt-4") -> Result:
    """Run agent to completion against the given model.

    Args:
        agent: The agent to execute.
        model: Model identifier to use for generation.

    Returns:
        The final Result once the agent loop terminates.
    """
    return _loop(agent, model)  # internal helper — no docstring
                                 # obligation, no stability obligation,
                                 # short name is fine at this scope
```

If a change would require *promoting* something from internal to public
(removing an underscore, adding it to `__all__`), say so explicitly and
confirm — that's a design decision with stability consequences, not a
formatting one, and it shouldn't happen silently as a side effect of an
unrelated edit.