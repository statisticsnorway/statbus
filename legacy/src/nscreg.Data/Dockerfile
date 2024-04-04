#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:7.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build
WORKDIR /src
COPY ["src/nscreg.Data/nscreg.Data.csproj", "src/nscreg.Data/"]
COPY ["src/nscreg.Utilities/nscreg.Utilities.csproj", "src/nscreg.Utilities/"]
COPY ["src/nscreg.Resources/nscreg.Resources.csproj", "src/nscreg.Resources/"]
RUN dotnet restore "src/nscreg.Data/nscreg.Data.csproj"
COPY . .
WORKDIR "/src/src/nscreg.Data"
RUN dotnet build "nscreg.Data.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "nscreg.Data.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "nscreg.Data.dll"]
