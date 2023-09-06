#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.
FROM mcr.microsoft.com/dotnet/aspnet:7.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM node:19-bullseye-slim AS spa-build
WORKDIR /src
COPY package*.json .
RUN npm ci --legacy-peer-deps
COPY jsconfig.json .
COPY client/. client/.
COPY tools/. tools/.
COPY appsettings.Shared.json .
RUN mkdir -p src/nscreg.Server/wwwroot/dist
RUN npm run build
ENTRYPOINT [ "/bin/sh" ]

FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build
ARG CONFIGURATION=Release
WORKDIR /src
COPY ["src/nscreg.Server/nscreg.Server.csproj", "src/nscreg.Server/"]
COPY ["src/nscreg.ModelGeneration/nscreg.ModelGeneration.csproj", "src/nscreg.ModelGeneration/"]
COPY ["src/nscreg.Utilities/nscreg.Utilities.csproj", "src/nscreg.Utilities/"]
COPY ["src/nscreg.Resources/nscreg.Resources.csproj", "src/nscreg.Resources/"]
COPY ["src/nscreg.Data/nscreg.Data.csproj", "src/nscreg.Data/"]
COPY ["Services/Services.csproj", "Services/"]
COPY ["src/nscreg.Business/nscreg.Business.csproj", "src/nscreg.Business/"]
COPY ["src/nscreg.Server.Common/nscreg.Server.Common.csproj", "src/nscreg.Server.Common/"]
RUN dotnet restore "src/nscreg.Server/nscreg.Server.csproj"

WORKDIR "/src/src/nscreg.Server"
COPY . /src
RUN dotnet build "nscreg.Server.csproj" -c ${CONFIGURATION} -f net7.0 --no-restore

FROM build AS publish
COPY --from=spa-build /src/src/nscreg.Server/. /src/src/nscreg.Server/
RUN dotnet publish "nscreg.Server.csproj" -c ${CONFIGURATION} -o /app/publish -f net7.0 --no-build

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "nscreg.Server.dll"]

