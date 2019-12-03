using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Connection settings class
    /// </summary>
    public class ConnectionSettings
    {
        public string ConnectionString { get; set; }
        public string Provider { get; set; }

        public ConnectionProvider ParseProvider()
        {
            if (Provider.Equals(ConnectionProvider.SqlServer.ToString(), StringComparison.OrdinalIgnoreCase))
                return ConnectionProvider.SqlServer;
            if (Provider.Equals(ConnectionProvider.PostgreSql.ToString(), StringComparison.OrdinalIgnoreCase))
                return ConnectionProvider.PostgreSql;
            return Provider.Equals(ConnectionProvider.MySql.ToString(), StringComparison.OrdinalIgnoreCase)
                ? ConnectionProvider.MySql
                : ConnectionProvider.InMemory;
        }
    }
}
