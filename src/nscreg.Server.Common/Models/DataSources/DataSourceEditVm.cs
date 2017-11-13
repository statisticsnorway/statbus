using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// Вью модель редактирования доступа к данным
    /// </summary>
    public class DataSourceEditVm
    {
        private DataSourceEditVm(DataSource item)
        {
            Name = item.Name;
            Description = item.Description;
            Priority = (int)item.Priority;
            AllowedOperations = (int)item.AllowedOperations;
            AttributesToCheck = item.AttributesToCheckArray;
            StatUnitType = (int)item.StatUnitType;
            Restrictions = item.Restrictions;
            VariablesMapping = item.VariablesMappingArray.Select(x => new[] {x.source, x.target});
            CsvDelimiter = item.CsvDelimiter;
            CsvSkipCount = item.CsvSkipCount;
        }

        /// <summary>
        /// Метод создания вью модели редактирования источника данных
        /// </summary>
        /// <param name="item">Единица</param>
        /// <returns></returns>
        public static DataSourceEditVm Create(DataSource item) => new DataSourceEditVm(item);

        public string Name { get; }
        public string Description { get; }
        public int Priority { get; }
        public int AllowedOperations { get; }
        public IEnumerable<string> AttributesToCheck { get; }
        public int StatUnitType { get; }
        public string Restrictions { get; }
        public IEnumerable<string[]> VariablesMapping { get; }
        public string CsvDelimiter { get; }
        public int CsvSkipCount { get; }
    }
}
