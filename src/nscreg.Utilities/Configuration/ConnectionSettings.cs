using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Класс настройки соединения
    /// </summary>
    public class ConnectionSettings
    {
        public string ConnectionString { get; set; }
        public string Provider { get; set; }

        public ConnectionProvider ParseProvider()
        {
            if (Provider.Equals(ConnectionProvider.SqlServer.ToString(), StringComparison.OrdinalIgnoreCase))
                return ConnectionProvider.SqlServer;
            return Provider.Equals(ConnectionProvider.PostgreSql.ToString(), StringComparison.OrdinalIgnoreCase)
                ? ConnectionProvider.PostgreSql
                : ConnectionProvider.InMemory;
        }
    }
}
