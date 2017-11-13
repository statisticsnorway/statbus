# development environment setup

* .NET Core and ASP.NET Core (included in Visual Studio 2017)
* Node.js 8.x.x (or newer)

.NET projects target `netcoreapp1.1` or `netstandard1.6`

## scripts

* _tools/run.js_ - build, bundle, publish and dev mode scripts
* _package.json_ - front-end dependencies and _run.js_ command hooks
  1. **npm install** - install all dependencies (both, client and server - e.g. **dotnet restore** in root)
  1. **npm start** - run app in development mode with file watchers and auto-reload of source code on update (Visual Studio debugger must be attached manually to debug backend app) - this way all scripts will be served from memory, not disk
  1. **npm run build:debug** - build and bundle scripts to disk (required if you run backend app from Visual Studio)
  1. **npm run build** - build and bundle production-ready scripts to disk
  1. ...other scripts to be described later - most of them is not executed directly

## local settings and Git

We use [secrets](https://docs.microsoft.com/en-us/aspnet/core/security/app-secrets) to store user-specific config (connection strings, etc.).
Sample `secrets.json` file:

```javascript
{
  "ConnectionSettings": {
    "ConnectionString": "",
    "Provider": "inmemory"
  },
}
```

## editors

### Visual Studio 2017

* ReSharper
* .ignore
* EditorConfig
* File icons
* Markdown Editor

### Visual Studio Code

* Babelrc
* CSS Modules
* EditorConfig for VS Code
* ESLint
* gitignore
* indent-rainbow
* markdownlint
* Path Intellisense
* PostCSS syntax
* stylelint
* vscode-icons
