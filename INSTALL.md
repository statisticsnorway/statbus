# STATBUS Technical Installation Guide

STATBUS is a business registry system developed by Statistics Norway (SSB) that helps track business activity throughout history using a temporal database. This guide will walk you through the steps necessary to install and run STATBUS on a local machine, configure it, and load sample data.

## Prerequisites

### General Requirements

Before installing STATBUS, ensure you have the following tools and services installed:

- **Git**: For source control and cloning the repository.
- **Docker**: For managing application containers.
- **Docker Compose**: To orchestrate multiple containers.

### System-specific Requirements

**Statbus Server Minimum Requirements:**

- **Operating System**: Linux (Ubuntu 24 LTS)
- **Ubuntu Upgrades**: Can be downloaded from Ubuntu Releases
- **CPU**: 4 cores
- **RAM**: 16 GB
- **Disk Space**: 10 GB

### Platform-Specific Setup

#### Linux (Ubuntu 24 LTS)

// AI! Add instructions to install git, docker and docker compose
##### Install Docker for running various services

Add Docker's official GPG key:
```
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
```

Add the repository to Apt sources:
```
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list
apt update

apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

NOTE: Docker compose circumvents UFW - so make sure you check what ports are exposed.
There is as of 2023-10 no known workaround, that does not prevent docker compose
hosts from reaching internet. This is handled by statbus through careful adjustments
of the docker compose setup from Supabase.



##### Install Crystal (Programming Language) compiler
```
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```


## Installation Steps

### Step 1: Clone the STATBUS Repository

Clone the repository from GitHub to your local machine:
```bash
git clone https://github.com/statisticsnorway/statbus.git
cd statbus
```

### Step 2: Configure Users

Create an initial users configuration file:
```bash
cp .users.example .users.yml
```
Edit the `.users.yml` file to add your admin access users.

### Step 3: Generate Configuration Files

Run the following command to generate the necessary configuration files:
```bash
./devops/manage-statbus.sh generate-config
```
This will create the `.env`, `.env.credentials`, and `.env.config` files, which are critical for running the system.

### Step 4: Start the Docker Containers

To start the Docker containers (which will include the database, API, and other required services):
```bash
./devops/manage-statbus.sh start required
```

### Step 5: Initialize and Seed the Database

For the first run, you will need to set up the database and seed it with initial data:
```bash
./devops/manage-statbus.sh activate_sql_saga
./devops/manage-statbus.sh create-db-structure
./devops/manage-statbus.sh create-users
```

### Step 6: Access the Application

Once the services are up and running, you can access STATBUS in your browser at:

- **Main Application**: [http://localhost:3000](http://localhost:3000)
- **Supabase Admin Panel**: [http://localhost:3001](http://localhost:3001)

Use the credentials in `.env.credentials` to log in to the Supabase admin panel.

## Managing Services

### Stopping and Restarting Services

To stop the services:
```bash
./devops/manage-statbus.sh stop
```

To restart the services:
```bash
./devops/manage-statbus.sh start required
```

### Teardown and Reset

To completely remove all data and configurations and start from scratch:
```bash
./devops/manage-statbus.sh stop
./devops/manage-statbus.sh delete-db
rm -f .env.credentials .env.config .env
```

## Local Development Setup

### Backend Services (Without the App)

To start the backend services without the frontend app:
```bash
./devops/manage-statbus.sh start required_not_app
```

### Frontend (App) Setup

#### Linux/Ubuntu and macOS

1. Navigate to the `app` folder:
   ```bash
   cd app
   ```

2. Activate the Node version specified in `.nvmrc`:
   ```bash
   nvm use
   ```

3. Start the application:
   ```bash
   npm run start
   ```

#### Windows (Using Git Bash)

1. Install the correct Node version:
   ```bash
   nvm install $(cat .nvmrc | tr -d '[:space:]')
   nvm use $(cat .nvmrc | tr -d '[:space:]')
   ```

2. Install dependencies and start the app:
   ```bash
   npm install
   npm run start
   ```

## Loading Sample Data

STATBUS includes sample dummy data for regions and units using ISIC4 activity categories. By downloading these files, you can see how a region_hierarchy is defined in a CSV file, and how activity categories can be modified.

- Use the command palette by pressing `Ctrl+Shift+K` to access data-loading options
- Load the demo files to get a working version of STATBUS running with data
- You can delete parts of the data using `Ctrl+Shift+K` and reload as needed
- Currently, STATBUS only delivers test data using ISIC as most STATBUS countries use this standard

## Git Configuration Notes

Ensure Git handles line endings correctly on Windows to avoid issues when running scripts or building Docker containers:
```bash
git config --global core.autocrlf true
```
This prevents Git from converting LF to CRLF, which could break the application.

## Conclusion

With this guide, you should now have a working local installation of STATBUS. You can start adding data, creating reports, and managing business activities over time. For further configuration or custom setups, refer to the official documentation.

---