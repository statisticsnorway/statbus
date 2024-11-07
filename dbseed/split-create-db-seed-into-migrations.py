#!/usr/bin/env python3

import os
import re
import json
import urllib.request
import urllib.error
import argparse
import hashlib
from pathlib import Path
from typing import List, Tuple

# Global variable to store the selected model
OLLAMA_MODEL = None

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Split SQL file into migrations using AI descriptions')
    parser.add_argument('--model', help='Specify Ollama model to use')
    return parser.parse_args()

def check_ollama_models(requested_model: str | None = None) -> None:
    """Check Ollama is running and set the global model."""
    global OLLAMA_MODEL
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:11434/api/tags",
            headers={'Content-Type': 'application/json'},
            method='GET'
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            models = json.loads(response.read())
            if not models['models']:
                print("Error: No models found in Ollama")
                raise SystemExit(1)
            available_models = [m['name'] for m in models['models']]

            if not available_models:
                print("Error: No models found in Ollama")
                raise SystemExit(1)

            if requested_model:
                if requested_model in available_models:
                    OLLAMA_MODEL = requested_model
                else:
                    print(f"Error: Requested model '{requested_model}' not found")
                    print(f"Available models: {', '.join(available_models)}")
                    raise SystemExit(1)
            else:
                print("Available models:", ', '.join(available_models))
                while True:
                    selection = input("Select a model (or press Enter for default): ").strip()
                    if not selection:
                        OLLAMA_MODEL = available_models[0]
                        break
                    if selection in available_models:
                        OLLAMA_MODEL = selection
                        break
                    print(f"Invalid selection. Available models: {', '.join(available_models)}")

            print(f"Using Ollama model: {OLLAMA_MODEL}")
    except Exception as e:
        print(f"Error: Cannot connect to Ollama service: {e}")
        print("Make sure Ollama is running and has models installed")
        raise SystemExit(1)

def get_ai_description(sql_content: str, index: int) -> str:
    global OLLAMA_MODEL
    """Get an AI-generated snake_case description for the SQL migration."""
    prompt = f"""
    Provide a brief snake_case description that captures the database objects produced, i.e. view name, table, name, function name, etc.
    Use only lowercase letters, numbers and underscores.
    Only write out the resulting description - no initial meta information.
    Example responses
    'create_users_table' or 'add_foreign_keys' or 'generate_table_x_for_import'
    or 'generate_view_x_for_custom_import', ...

    ```
    {sql_content}
    ```
    """

    try:
        data = json.dumps({
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False
        }).encode('utf-8')

        req = urllib.request.Request(
            "http://127.0.0.1:11434/api/generate",
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=360) as response:
            result = json.loads(response.read())["response"].strip()
        # Ensure snake_case format
        result = re.sub(r'[^a-z0-9_]', '_', result.lower())
        result = re.sub(r'_+', '_', result)  # Remove multiple underscores
        result = result.strip('_')
        result = result[:128]  # Limit length

        return result
    except Exception as e:
        print(f"Error: AI description failed: {e}")
        raise SystemExit(1)

class InputParser:
    def __init__(self):
        self.buffer = []
        self.newline_count = 0
        self.migration_count = 0

    def process_char(self, char: str) -> bool:
        """Process a single character and return True if we have a complete migration."""
        if char == '\n':
            self.newline_count += 1
        else:
            if self.newline_count >= 3 and self.buffer:
                return True
            self.newline_count = 0

        if not (self.newline_count >= 3):
            self.buffer.append(char)
        return False

    def get_migration(self) -> str:
        """Return the current migration and reset buffer."""
        content = ''.join(self.buffer).strip()
        self.buffer = []
        self.newline_count = 0
        return content

def process_migration(sql_content: str, migration_number: int, migrations_dir: Path) -> None:
    """Process a single migration and write it to file."""
    if not sql_content:
        return

    print(f"Migration {migration_number:04d}: Processing...", end="", flush=True)
    content_hash = hashlib.sha256(sql_content.encode()).hexdigest()

    existing_files = list(migrations_dir.glob(f"{migration_number:04d}_*.up.sql"))

    if existing_files:
        existing_path = existing_files[0]
        with open(existing_path, 'r') as existing:
            existing_content = existing.read()
            existing_hash = hashlib.sha256(existing_content.encode()).hexdigest()

        if existing_hash == content_hash:
            print(f" {existing_path.stem[5:]} (unchanged)", flush=True)
            return

        # Only get AI description if content changed
        description = get_ai_description(sql_content, migration_number)
        print(f" {description}", end="", flush=True)
        filename = f"{migration_number:04d}_{description}.up.sql"
        output_path = migrations_dir / filename

        if existing_path.name != filename:
            existing_path.unlink()
        print(" (updated)", end="", flush=True)
    else:
        # New migration - get AI description
        description = get_ai_description(sql_content, migration_number)
        print(f" {description}", end="", flush=True)
        filename = f"{migration_number:04d}_{description}.up.sql"
        output_path = migrations_dir / filename

    # Write new content
    with open(output_path, 'w') as out:
        out.write(sql_content)
    print(f" -> {filename}", flush=True)

def process_sql_file(input_file: Path, migrations_dir: Path) -> None:
    """Process SQL file character by character and write migrations incrementally."""
    parser = InputParser()

    with open(input_file, 'r') as f:
        while char := f.read(1):
            if parser.process_char(char):
                # We have a complete migration
                parser.migration_count += 1
                sql_content = parser.get_migration()
                process_migration(sql_content, parser.migration_count, migrations_dir)

        # Handle final migration if any
        if parser.buffer:
            parser.migration_count += 1
            sql_content = parser.get_migration()
            process_migration(sql_content, parser.migration_count, migrations_dir)

def main():
    args = parse_args()
    # Check Ollama models at startup
    check_ollama_models(args.model)

    # Setup paths
    input_file = Path("dbseed/create-db-structure.sql")
    migrations_dir = Path("migrations")

    # Create migrations directory
    migrations_dir.mkdir(exist_ok=True)

    # Process SQL file and write migrations
    process_sql_file(input_file, migrations_dir)

if __name__ == "__main__":
    main()
