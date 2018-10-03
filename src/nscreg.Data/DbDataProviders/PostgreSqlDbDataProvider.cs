using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbDataProviders
{
    public class PostgreSqlDbDataProvider : IDbDataProvider
    {
        public async Task<List<ReportTree>> GetReportsTree(NSCRegDbContext context, string sqlWalletUser, IConfiguration config)
        {
            List<ReportTree> reportTree = new List<ReportTree>();

            string connectionString = config.GetSection(nameof(ReportingSettings)).Get<ReportingSettings>().ConnectionString;
            using (var connection = new SqliteConnection(connectionString))
            {
                connection.Open();
                using (var command = new SqliteCommand())
                {
                    command.Connection = connection;
                    command.CommandText = @"SELECT 
                                            Id,
                                            Title,
                                            Type,
                                            ReportId,
                                            ParentNodeId,
                                            IsDeleted,
                                            ResourceGroup,
                                            NULL as ReportUrl
                                            From ReportTreeNode rtn
                                            Where rtn.IsDeleted = 0
                                   And (rtn.ReportId is null or rtn.ReportId in (Select distinct ReportId From ReportAce where Principal = '" + sqlWalletUser + "'))";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            reportTree.Add(new ReportTree()
                            {
                                Id = reader.GetInt32(0),
                                Title = reader.GetValue(1) != DBNull.Value ? reader.GetString(1) : default(string),
                                Type = reader.GetValue(2) != DBNull.Value ? reader.GetString(2) : default(string),
                                ReportId = reader.GetValue(3) != DBNull.Value ? reader.GetInt32(3) : default(int?),
                                ParentNodeId = reader.GetValue(4) != DBNull.Value ? reader.GetInt32(4) : default(int?),
                                IsDeleted = reader.GetBoolean(5),
                                ResourceGroup = reader.GetValue(6) != DBNull.Value ? reader.GetString(6) : default(string),
                                ReportUrl = reader.GetValue(6) != DBNull.Value ? reader.GetString(6) : default(string),
                            });

                        }
                    }
                }
                if (connection.State == ConnectionState.Open)
                {
                    connection.Close();
                }
            }          

            return reportTree;
        }

        public int[] GetActivityChildren(NSCRegDbContext context, object fieldValue)
        {
            return context.ActivityCategories.FromSql(@"SELECT * FROM ""GetActivityChildren""({0})", Convert.ToInt32(fieldValue)).Select(x => x.Id)
                .ToArray();
        }

        public int[] GetRegionChildren(NSCRegDbContext context, object fieldValue)
        {
            return context.Regions.FromSql(@"SELECT * FROM ""GetRegionChildren""({0})", Convert.ToInt32(fieldValue)).Select(x => x.Id)
                .ToArray();
        }
    }
}
