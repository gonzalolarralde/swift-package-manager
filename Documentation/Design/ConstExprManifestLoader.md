# Experimental ConstExpr Manifest Loading

This branch prototypes a manifest fast path that evaluates a restricted,
side-effect-free subset of `Package.swift` in the SwiftPM process. It is an
alternative to a handwritten PackageDescription syntax decoder and is not the
default manifest loader.

The loader, its command-line modes, and its host-evaluation bridge are all
experimental implementation details. They make no source, ABI, or API
compatibility promise; the implementation types are package-scoped and are not
part of SwiftPM's public library products.

## Pipeline

For a tools-version 5.0-or-newer manifest, the loader:

1. Parses the original source and selects active `#if` regions using the host
   toolchain's compiler flags, SDK, target, PackageDescription version, and
   compiler environment.
2. Audits the active top level and requires a valid `PackageDescription`
   import, immutable global bindings, and exactly one `package` value.
3. Evaluates the typed global `Package` value in certifying mode using the
   PackageDescription ConstExpr registry.
4. Serializes that value through a PackageDescription-only JSON SPI.
5. Passes the canonical JSON to SwiftPM's existing `ManifestJSONParser`.

The terminal-value API avoids rewriting source, emitting a large string
literal, compiling rewritten Swift, loading a manifest executable, or running
it in a sandbox.

## Modes and fallback

`only-executed` remains the default. The experimental flag
`--experimental-manifest-processing-mode` also accepts:

- `only-constexpr`, which exposes a fast-path miss as an error.
- `constexpr-with-fallback`, which executes the untouched original manifest
  whenever the fast path cannot certify it.
- `crosscheck`, which loads with both implementations and compares canonical
  final manifests after a successful fast evaluation.

Normal fallback is silent. Syntax errors, unknown names, unavailable or
ambiguous overloads, unsupported effects, and adapter failures are delegated to
the executing loader so Swift compiler diagnostics stay authoritative. The
hidden `--experimental-show-constexpr-manifest-fallbacks` flag exposes
structured reason codes through SwiftPM observability for development; it does
not write telemetry into command stdout.

Fallback receives the byte-for-byte original source. In particular, mutation
such as `package.targets.append(...)` is currently a deliberate fast-path miss.
Deprecated language-standard spellings remain misses so the compiler can emit
their warnings. Current language modes and standards are supported.
Typed and string-valued platform versions, including `custom`, are supported.

## Supported context and API surface

The registry targets current, non-obsoleted PackageDescription APIs for
packages, products, targets, dependencies, versions, platforms, traits,
resources, plug-in usages, and build settings. It models structural Optional,
Array, Dictionary, Set, range, and tuple values rather than registering every
concrete container type.

PackageDescription 5.0 through 5.10 use availability-bounded adapters for
historical `Package` and `Target` factories, dependency requirements, and
conditions. Each adapter preserves its source-era labels and defaults while
constructing the equivalent current model. Once an old spelling becomes
deprecated or obsolete, it is excluded so the Swift compiler remains the
source of diagnostics.

Active manifests can read `Context.packageDirectory`, `Context.environment`,
and `Context.gitInformation`. SwiftPM injects these values without exposing
process access to the evaluator. Inactive `#if` branches need not be evaluable.

PackageDescription annotations and their generated registration peers are
compiled only with `SWIFTPM_CONSTEXPR_MANIFESTS`. Peers are package-scoped, and
the public PackageDescription interface must contain neither ConstExpr imports
nor generated provider names. The ordinary CMake/bootstrap source list omits
the JSON SPI and has no ConstExpr dependency. The SwiftPM package graph uses a
prototype-only local dependency at `../../swift-constexpr`.

## Coverage and performance

The Package Index harness lives in the local `swift-constexpr` checkout:

```sh
cd /path/to/swift-constexpr
python3 Scripts/PackageIndex/run.py --swiftpm /path/to/swiftpm --limit 100
```

Use `--all` for the pinned complete list and `--crosscheck` for the deterministic
clone-backed comparison sample. The opt-in PackageLoading test processes the
JSONL input in one process and streams resumable JSONL output containing status,
reason, tools version, content hash, and per-manifest duration.

Run the release benchmark with its stable XCTest selector:

```sh
cd /path/to/swiftpm
SWIFTPM_CONSTEXPR_BENCHMARK=1 \
swift test -c release \
  --filter PackageLoadingTests.ConstExprManifestLoaderPerformanceTests/testRepresentativeManifestBenchmark
```

Set `SWIFTPM_CONSTEXPR_BENCHMARK_ITERATIONS` to change the warm sample count.
The test prints cold, warm mean, median, p90, and p99 nanoseconds. To collect
ConstExpr signposts in Instruments, also set
`SWIFTPM_CONSTEXPR_SIGNPOSTS=1`; production defaults keep them disabled.
