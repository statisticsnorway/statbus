#!/usr/bin/env python3

import os
import glob
from pathlib import Path

def ensure_begin_end(file_path):
    """Ensure SQL file has BEGIN and END statements"""
    with open(file_path, 'r') as f:
        content = f.read().strip()
    
    # Check if BEGIN/END already exist (case insensitive)
    has_begin = 'BEGIN;' in content.upper()
    has_end = 'END;' in content.upper()
    
    # Add missing statements
    if not has_begin:
        content = 'BEGIN;\n\n' + content
    if not has_end:
        content = content + '\n\nEND;'
    
    # Write back
    with open(file_path, 'w') as f:
        f.write(content)

def main():
    # Get all .sql files in migrations directory
    migrations_dir = Path('migrations')
    if not migrations_dir.exists():
        print("Error: migrations directory not found")
        return
    
    sql_files = glob.glob('migrations/**/*.sql', recursive=True)
    
    for sql_file in sql_files:
        print(f"Processing {sql_file}...")
        ensure_begin_end(sql_file)
        print(f"Updated {sql_file}")

if __name__ == '__main__':
    main()
