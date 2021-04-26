using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.Analysis.Contracts;
using nscreg.Data;
using nscreg.Data.Entities;
using NLog;

namespace nscreg.Business.Analysis.StatUnit.Managers.AnalysisChecks
{
    internal class StatUnitCustomCheckManager : IAnalysisManager
    {
        private readonly IStatisticalUnit _statUnit;
        private readonly NSCRegDbContext _context;
        private static readonly string ParamsRegex = @"@(\w+)";
        private static Logger _logger = LogManager.GetCurrentClassLogger();

        public StatUnitCustomCheckManager(IStatisticalUnit statUnit, NSCRegDbContext context)
        {
            _statUnit = statUnit;
            _context = context;
        }

        public Dictionary<string, string[]> CheckFields()
        {
            var result = new Dictionary<string, string[]>();
            var customChecks = GetCustomChecks();

            foreach (var check in customChecks)
            {
                try
                {
                    DoCheck(check, result);
                }
                catch (Exception e)
                {
                    _logger.Error(e, $"Error while trying to execute custom analysis check: id={check.Id}, query={check.Query}");
                }
            }
            return result;
        }

        private void DoCheck(CustomAnalysisCheck check, Dictionary<string, string[]> result)
        {
            var paramNames = GetParamNames(check.Query);
            var paramsCollection = paramNames.Select(x => new SqlParameter(x, GetValueOrDefault(x)));
            var queryCommand = $"{check.Query} and RegId = {_statUnit.RegId}";
            using (var command = _context.Database.GetDbConnection().CreateCommand())
            {
                command.CommandText = queryCommand;
                command.Parameters.AddRange(paramsCollection.ToArray());
                _context.Database.OpenConnection();
                using (var reader = command.ExecuteReader())
                {
                    var values = new List<string>();
                    while (reader.Read())
                    {
                        values.Add(reader.GetInt32(0).ToString());
                        result[check.Name] = values.ToArray();
                    }
                }
            }
        }

        private object GetValueOrDefault(string name)
        {
            var property = _statUnit.GetType().GetProperty(name);
            if (property == null)
            {
                _logger.Info($"{_statUnit.GetType().FullName} class doesn't have property {name}");
            }
            return property?.GetValue(_statUnit);
        }

        private IEnumerable<string> GetParamNames(string checkQuery)
        {
            return from Match match in Regex.Matches(checkQuery, ParamsRegex) select match.Groups[1].Value;
        }

        private IEnumerable<CustomAnalysisCheck> GetCustomChecks()
        {
            return _context.CustomAnalysisChecks
                .Where(x => x.TargetUnitTypes.Contains(_statUnit.UnitType.ToString()))
                .ToList();
        }
    }
}
