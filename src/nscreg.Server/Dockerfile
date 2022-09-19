#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:3.1 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:3.1 AS build
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y libpng-dev libjpeg-dev curl libxi6 build-essential libgl1-mesa-glx
RUN curl -sL https://deb.nodesource.com/setup_lts.x | bash -
RUN apt-get install -y nodejs
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
COPY . .
RUN npm ci --legacy-peer-deps
RUN npm run build 
WORKDIR "/src/src/nscreg.Server"
RUN dotnet build "nscreg.Server.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "nscreg.Server.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "nscreg.Server.dll"]