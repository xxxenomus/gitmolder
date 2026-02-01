# gitmolder, an open-source ROBLOX Git Sync Plugin

A Roblox Studio plugin that enables synchronization with GitHub repositories. Push and pull code directly from your Roblox game project to GitHub. Perfect application if you want any sort of source control without Rojo and any sort of external code editor.

## Features

-  **GitHub Integration** - Connect your Roblox projects to GitHub repositories
-  **v1.0: Push to GitHub** - Sync your local changes to a remote GitHub repository
-  **Pull from GitHub** - Fetch the latest code from your repository (v1.0 & v1.1)

## Requirements

- **Roblox Studio** - The plugin is designed for Roblox Studio
- **HTTP Requests Enabled** - Enable in Game Settings -> Security -> Allow HTTP Requests
- **GitHub Personal Access Token** - Required for API authentication

## Installation

1. Download the version folder
2. Place in Roblox studio workspace
3. Right-click the folder and save as local plugin
3. Enable HTTP requests in experience settings

## Usage

1. Click **GM settings** in the toolbar to enter GitHub credentials
2. Click **Gitmolder** in the toolbar to open the sync widget
3. Use the available buttons:
   - **v1.0**: Push / Pull / Cancel
   - **v1.1**: Push / Cancel (pull removed)

   
More features might be added later, including commiting before push and merge conflict handling.
