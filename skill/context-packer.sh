#!/usr/bin/env bash
# Context Packer - Aggregates files into a single context document
# Part of Upgrade #8: Prompt Compression & Context Sharing
#
# Usage: ./context-packer.sh <output_file> <input_file1> [input_file2...]
#
# Example:
#   ./context-packer.sh /tmp/shared-context.md src/types.ts docs/guidelines.md

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <output_file> <input_file1> [input_file2...]"
  exit 1
fi

OUTPUT_FILE="$1"
shift
INPUT_FILES=("$@")

# Create header
cat > "$OUTPUT_FILE" << EOF
# Shared Context

The following files provide shared context for your task.
Read these definitions and guidelines before implementing your changes.

EOF

# Append each file
COUNT=0
for file in "${INPUT_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    # Use relative path if possible for cleaner context
    REL_PATH="$file"
    if [[ "$file" == "$(pwd)"* ]]; then
      REL_PATH="${file#$(pwd)/}"
    fi

    echo "## File: $REL_PATH" >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    ((COUNT++))
  else
    echo "Warning: Input file not found: $file" >&2
  fi
done

echo "Packed $COUNT files into $OUTPUT_FILE"
