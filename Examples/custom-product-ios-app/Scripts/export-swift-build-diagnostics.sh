#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${IOS_DEMO_BUILD_ROOT:-$DEMO_ROOT/.build}"
XCBUILD_DATA_ROOT="$BUILD_ROOT/out/Intermediates.noindex/XCBuildData"
PIF_PATH="$BUILD_ROOT/manifest.pif"
OUTPUT_ROOT="${1:-$DEMO_ROOT/.demo-runtime/swift-build-diagnostics}"

if [[ ! -f "$PIF_PATH" ]]; then
    echo "error: no PIF found at $PIF_PATH; build the example first" >&2
    exit 1
fi
if [[ ! -d "$XCBUILD_DATA_ROOT" ]]; then
    echo "error: no Swift Build descriptions found at $XCBUILD_DATA_ROOT" >&2
    exit 1
fi

LATEST_DATA_DIR=""
LATEST_DATA_MTIME=0
while IFS= read -r candidate; do
    candidate_mtime="$(stat -f '%m' "$candidate")"
    if (( candidate_mtime > LATEST_DATA_MTIME )); then
        LATEST_DATA_DIR="$candidate"
        LATEST_DATA_MTIME="$candidate_mtime"
    fi
done < <(find "$XCBUILD_DATA_ROOT" -maxdepth 1 -type d -name '*.xcbuilddata' -print)

if [[ -z "$LATEST_DATA_DIR" ]] ||
   [[ ! -f "$LATEST_DATA_DIR/manifest.json" ]] ||
   [[ ! -f "$LATEST_DATA_DIR/build-request.json" ]]; then
    echo "error: the latest Swift Build description is incomplete" >&2
    exit 1
fi

mkdir -p "$OUTPUT_ROOT"
rm -rf "$OUTPUT_ROOT/nested-builds"

# Raw inputs. These are copied without filtering so the export remains useful
# when inspecting fields that the normalized reports below intentionally omit.
jq . "$PIF_PATH" > "$OUTPUT_ROOT/pif.json"
jq . "$LATEST_DATA_DIR/build-request.json" > "$OUTPUT_ROOT/build-request.json"
jq . "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/llbuild-manifest.json"
cp "$LATEST_DATA_DIR/target-graph.txt" "$OUTPUT_ROOT/target-graph.txt"
for opaque_build_description_file in description.msgpack task-store.msgpack; do
    if [[ -f "$LATEST_DATA_DIR/$opaque_build_description_file" ]]; then
        cp \
            "$LATEST_DATA_DIR/$opaque_build_description_file" \
            "$OUTPUT_ROOT/$opaque_build_description_file"
    fi
done

# The PIF is the client-side workspace/project/target model. It is not the
# execution task list. This report makes that model boundary explicit.
jq '
    [.[] | select(.type == "target") | {
        name: .contents.name,
        guid: .contents.guid,
        targetKind: .contents.type,
        productTypeIdentifier: (.contents.productTypeIdentifier // null),
        dependencyGUIDs: [(.contents.dependencies // [])[].guid],
        customTaskCount: ((.contents.customTasks // []) | length)
    }]
' "$PIF_PATH" > "$OUTPUT_ROOT/pif-targets.json"

jq -r '
    (["object_type", "count"] | @csv),
    (. | group_by(.type)[] | [.[0].type, length] | @csv)
' "$PIF_PATH" > "$OUTPUT_ROOT/pif-object-counts.csv"

# Swift Build expands configured PIF targets through task producers into
# PlannedTasks, which are serialized as commands in this llbuild manifest.
jq '
    .commands
    | to_entries
    | map({
        id: .key,
        tool: (.value.tool // "unknown"),
        description: (.value.description // ""),
        commandLine: (.value.args // []),
        workingDirectory: (.value.workingDirectory // null),
        inputs: (.value.inputs // []),
        outputs: (.value.outputs // []),
        environmentVariableCount: ((.value.env // {}) | length)
    })
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/tasks.json"

jq '
    [.commands
    | to_entries[]
    | select(.value.tool != "phony")
    | {
        id: .key,
        tool: (.value.tool // "unknown"),
        description: (.value.description // ""),
        commandLine: (.value.args // []),
        inputs: (.value.inputs // []),
        outputs: (.value.outputs // [])
    }]
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/executable-tasks.json"

jq '
    [.commands
    | to_entries[]
    | select(.value.tool == "phony")
    | {
        id: .key,
        description: (.value.description // ""),
        inputs: (.value.inputs // []),
        outputs: (.value.outputs // [])
    }]
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/ordering-gates.json"

jq -r '
    (["id", "tool", "description", "input_count", "output_count"] | @csv),
    (.commands
    | to_entries[]
    | [
        .key,
        (.value.tool // "unknown"),
        (.value.description // ""),
        ((.value.inputs // []) | length),
        ((.value.outputs // []) | length)
    ]
    | @csv)
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/tasks.csv"

jq -r '
    (["tool", "count"] | @csv),
    ([.commands[].tool // "unknown"]
    | group_by(.)
    | map({tool: .[0], count: length})
    | sort_by(-.count, .tool)[]
    | [.tool, .count]
    | @csv)
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/task-kind-counts.csv"

# Preserve the product-builder PlannedTask separately, without the expanded
# Xcode build-setting environment that is already available in the raw file.
jq '
    [.commands
    | to_entries[]
    | select((.value.description // "") | startswith("CustomTask Packaging IOSDemoIPA"))
    | {
        id: .key,
        tool: .value.tool,
        description: .value.description,
        commandLine: .value.args,
        workingDirectory: .value.workingDirectory,
        inputs: .value.inputs,
        outputs: .value.outputs,
        environmentVariableNames: ((.value.env // {}) | keys)
    }]
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/product-builder-task.json"

# For every declared input/output of the builder, show the producer or
# consumers that make the data edges concrete in the llbuild graph.
jq '
    .commands as $commands
    | ($commands
        | to_entries[]
        | select((.value.description // "") | startswith("CustomTask Packaging IOSDemoIPA"))) as $custom
    | {
        customTaskID: $custom.key,
        inputEdges: [
            $custom.value.inputs[] as $input
            | {
                node: $input,
                producers: [
                    $commands
                    | to_entries[]
                    | select((.value.outputs // []) | index($input))
                    | .key
                ]
            }
        ],
        outputEdges: [
            $custom.value.outputs[] as $output
            | {
                node: $output,
                consumers: [
                    $commands
                    | to_entries[]
                    | select((.value.inputs // []) | index($output))
                    | .key
                ]
            }
        ]
    }
' "$LATEST_DATA_DIR/manifest.json" > "$OUTPUT_ROOT/product-builder-edges.json"

# llbuild's SQLite database is persistent across build descriptions. These
# rows describe the last execution remembered for command rules, not a new
# chronological trace of the most recent null build.
BUILD_DATABASE="$XCBUILD_DATA_ROOT/build.db"
if [[ -f "$BUILD_DATABASE" ]]; then
    sqlite3 -header -csv "$BUILD_DATABASE" '
        SELECT
            substr(key_names.key, 2) AS llbuild_command_id,
            rule_results.built_at,
            rule_results.computed_at,
            printf("%.6f", rule_results.end - rule_results.start) AS recorded_seconds
        FROM key_names
        JOIN rule_results ON rule_results.key_id = key_names.id
        WHERE substr(key_names.key, 1, 1) = "C"
        ORDER BY rule_results.built_at, key_names.id
    ' > "$OUTPUT_ROOT/build-db-command-history.csv"

    sqlite3 -header -csv "$BUILD_DATABASE" '
        SELECT
            rule_results.built_at,
            count(*) AS rule_count,
            printf("%.6f", sum(rule_results.end - rule_results.start)) AS recorded_seconds
        FROM rule_results
        GROUP BY rule_results.built_at
        ORDER BY rule_results.built_at
    ' > "$OUTPUT_ROOT/build-db-generation-summary.csv"
fi

# The outer custom task launches xcodebuild. That nested build has its own
# independently planned Swift Build graph, which is deliberately opaque to the
# outer graph. Export every nested build description that the demo retained.
NESTED_INDEX="$OUTPUT_ROOT/nested-builds.ndjson"
rm -f "$NESTED_INDEX"
while IFS= read -r nested_manifest; do
    nested_description="$(dirname "$nested_manifest")"
    if [[ "$nested_manifest" == *"-simulator/"* ]]; then
        nested_name="simulator-app"
    else
        nested_name="device-archive"
    fi
    nested_output="$OUTPUT_ROOT/nested-builds/$nested_name"
    mkdir -p "$nested_output"

    jq . "$nested_manifest" > "$nested_output/llbuild-manifest.json"
    if [[ -f "$nested_description/build-request.json" ]]; then
        jq . "$nested_description/build-request.json" > "$nested_output/build-request.json"
    fi
    if [[ -f "$nested_description/target-graph.txt" ]]; then
        cp "$nested_description/target-graph.txt" "$nested_output/target-graph.txt"
    fi
    for opaque_build_description_file in description.msgpack task-store.msgpack; do
        if [[ -f "$nested_description/$opaque_build_description_file" ]]; then
            cp \
                "$nested_description/$opaque_build_description_file" \
                "$nested_output/$opaque_build_description_file"
        fi
    done
    jq '
        .commands
        | to_entries
        | map({
            id: .key,
            tool: (.value.tool // "unknown"),
            description: (.value.description // ""),
            commandLine: (.value.args // []),
            workingDirectory: (.value.workingDirectory // null),
            inputs: (.value.inputs // []),
            outputs: (.value.outputs // []),
            environmentVariableCount: ((.value.env // {}) | length)
        })
    ' "$nested_manifest" > "$nested_output/tasks.json"
    jq '
        [.commands
        | to_entries[]
        | select(.value.tool != "phony")
        | {
            id: .key,
            tool: (.value.tool // "unknown"),
            description: (.value.description // ""),
            commandLine: (.value.args // []),
            inputs: (.value.inputs // []),
            outputs: (.value.outputs // [])
        }]
    ' "$nested_manifest" > "$nested_output/executable-tasks.json"
    jq '
        [.commands
        | to_entries[]
        | select(.value.tool == "phony")
        | {
            id: .key,
            description: (.value.description // ""),
            inputs: (.value.inputs // []),
            outputs: (.value.outputs // [])
        }]
    ' "$nested_manifest" > "$nested_output/ordering-gates.json"
    jq -r '
        (["id", "tool", "description", "input_count", "output_count"] | @csv),
        (.commands
        | to_entries[]
        | [
            .key,
            (.value.tool // "unknown"),
            (.value.description // ""),
            ((.value.inputs // []) | length),
            ((.value.outputs // []) | length)
        ]
        | @csv)
    ' "$nested_manifest" > "$nested_output/tasks.csv"
    jq -r '
        (["tool", "count"] | @csv),
        ([.commands[].tool // "unknown"]
        | group_by(.)
        | map({tool: .[0], count: length})
        | sort_by(-.count, .tool)[]
        | [.tool, .count]
        | @csv)
    ' "$nested_manifest" > "$nested_output/task-kind-counts.csv"

    nested_database="$(dirname "$nested_description")/build.db"
    if [[ -f "$nested_database" ]]; then
        sqlite3 -header -csv "$nested_database" '
            SELECT
                substr(key_names.key, 2) AS llbuild_command_id,
                rule_results.built_at,
                rule_results.computed_at,
                printf("%.6f", rule_results.end - rule_results.start) AS recorded_seconds
            FROM key_names
            JOIN rule_results ON rule_results.key_id = key_names.id
            WHERE substr(key_names.key, 1, 1) = "C"
            ORDER BY rule_results.built_at, key_names.id
        ' > "$nested_output/build-db-command-history.csv"
    fi

    jq -n \
        --arg name "$nested_name" \
        --arg source "$nested_description" \
        --slurpfile manifest "$nested_manifest" '
        {
            name: $name,
            source: $source,
            commandCount: ($manifest[0].commands | length),
            orderingGateCount: ([
                $manifest[0].commands[]
                | select(.tool == "phony")
            ] | length),
            executableTaskCount: ([
                $manifest[0].commands[]
                | select(.tool != "phony")
            ] | length),
            commandKinds: ([
                $manifest[0].commands[].tool // "unknown"
            ]
            | group_by(.)
            | map({tool: .[0], count: length})
            | sort_by(-.count, .tool))
        }
    ' > "$nested_output/summary.json"
    jq -c . "$nested_output/summary.json" >> "$NESTED_INDEX"
done < <(
    find "$BUILD_ROOT/plugins" \
        -type f \
        -name manifest.json \
        -path '*XCBuildData/*.xcbuilddata/manifest.json' \
        -print 2>/dev/null \
        | sort
)

if [[ -f "$NESTED_INDEX" ]]; then
    jq -s . "$NESTED_INDEX" > "$OUTPUT_ROOT/nested-builds/index.json"
    rm "$NESTED_INDEX"
else
    mkdir -p "$OUTPUT_ROOT/nested-builds"
    jq -n '[]' > "$OUTPUT_ROOT/nested-builds/index.json"
fi

jq -n \
    --arg generatedAt "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg pif "$PIF_PATH" \
    --arg buildDescription "$LATEST_DATA_DIR" \
    --slurpfile pifData "$PIF_PATH" \
    --slurpfile manifest "$LATEST_DATA_DIR/manifest.json" \
    --slurpfile nestedBuilds "$OUTPUT_ROOT/nested-builds/index.json" '
    {
        generatedAt: $generatedAt,
        sources: {
            pif: $pif,
            buildDescription: $buildDescription
        },
        pif: {
            objectCount: ($pifData[0] | length),
            workspaceCount: ([$pifData[0][] | select(.type == "workspace")] | length),
            projectCount: ([$pifData[0][] | select(.type == "project")] | length),
            targetCount: ([$pifData[0][] | select(.type == "target")] | length),
            customTaskCount: ([
                $pifData[0][]
                | select(.type == "target")
                | (.contents.customTasks // [])[]
            ] | length)
        },
        executionManifest: {
            commandCount: ($manifest[0].commands | length),
            orderingGateCount: ([
                $manifest[0].commands[]
                | select(.tool == "phony")
            ] | length),
            executableTaskCount: ([
                $manifest[0].commands[]
                | select(.tool != "phony")
            ] | length),
            productBuilderTaskCount: ([
                $manifest[0].commands[]
                | select((.description // "") | startswith("CustomTask Packaging IOSDemoIPA"))
            ] | length),
            commandKinds: ([
                $manifest[0].commands[].tool // "unknown"
            ]
            | group_by(.)
            | map({tool: .[0], count: length})
            | sort_by(-.count, .tool))
        },
        nestedXcodeBuilds: $nestedBuilds[0]
    }
' > "$OUTPUT_ROOT/summary.json"

echo "Swift Build diagnostics exported to:"
echo "$OUTPUT_ROOT"
echo
jq . "$OUTPUT_ROOT/summary.json"
