# Integration

## REST API

This guide helps you integrate with the StatBus REST API using Python or R.

### Getting Your API Key

1. Log into your StatBus instance using a web browser
2. Visit the API key endpoint: `https://your-statbus-url/rest/api_key?select=token`
3. Copy the token value displayed

### Setting Up Your Environment

Both Python and R examples use a `.env` file to store configuration. This file should be created in the same directory as your scripts.

Create a `.env` file with the following content:

```bash
API_URL=https://your-statbus-url
API_KEY=your-api-key-here
```

**Important:** 
- Replace `https://your-statbus-url` with your actual StatBus instance URL (e.g., `https://dev.statbus.org`)
- Replace `your-api-key-here` with the token you copied from the API key endpoint
- Never commit the `.env` file to version control (it should be in `.gitignore`)

### Quick Start

Choose your preferred language:

#### Python
```bash
cd python/
./setup.sh
source .venv/bin/activate  # Activate the virtual environment
python example.py
```

See [python/README.md](python/README.md) for detailed Python instructions.

#### R
```bash
cd r/
./setup.sh
Rscript example.r
```

See [r/README.md](r/README.md) for detailed R instructions.

### What the Setup Scripts Do

Both `setup.sh` scripts will:
1. Check if required tools (Python/R) are installed
2. Create a `.env` file template if it doesn't exist
3. Install necessary packages/libraries
4. Test the API connection using your credentials
5. Confirm everything is working correctly

After running the setup script successfully, you can run the example scripts to fetch and visualize data from StatBus.