#!/bin/sh
# Apply SSLSNI patch to pgAdmin server_manager.py
# This converts boolean values (true/false) to integers (1/0) for
# sslcompression and sslsni parameters, which libpq requires
#
# Based on https://github.com/pgadmin-org/pgadmin4/pull/9537

set -e

PATCH_TARGET="/pgadmin4/pgadmin/utils/driver/psycopg3/server_manager.py"

if [ ! -f "$PATCH_TARGET" ]; then
    echo "WARNING: Could not find server_manager.py at expected location."
    echo "SSLSNI fix may already be included in this pgAdmin version."
    exit 0
fi

if grep -q "sslcompression.*sslsni" "$PATCH_TARGET"; then
    echo "SSLSNI patch already applied, skipping."
    exit 0
fi

echo "Applying SSLSNI patch to $PATCH_TARGET"

# Create a Python script to do the patching (more reliable than sed for Python files)
python3 << 'PATCHSCRIPT'
import re

target_file = "/pgadmin4/pgadmin/utils/driver/psycopg3/server_manager.py"

with open(target_file, 'r') as f:
    content = f.read()

# Find the pattern: "if key == 'hostaddr' and self.use_ssh_tunnel:"
# and add our fix after the "continue" statement that follows it
pattern = r"(if key == 'hostaddr' and self\.use_ssh_tunnel:\s+continue)"
replacement = r'''\1

                # Convert boolean connection parameters to integer for libpq compatibility
                if key in ('sslcompression', 'sslsni'):
                    value = 1 if value else 0'''

new_content, count = re.subn(pattern, replacement, content)

if count == 0:
    print("WARNING: Could not find expected pattern to patch.")
    print("The file structure may have changed. Manual patching may be required.")
    exit(1)

with open(target_file, 'w') as f:
    f.write(new_content)

print(f"SSLSNI patch applied successfully ({count} replacement(s)).")
PATCHSCRIPT

echo "SSLSNI patch completed."
