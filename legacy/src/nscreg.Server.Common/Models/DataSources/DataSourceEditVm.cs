using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// View data access editing model
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
            OriginalCsvAttributes = item.OriginalAttributesArray;
            VariablesMapping = item.VariablesMappingArray.Select(x => new[] {item.OriginalAttributesArray.ElementAt(item.VariablesMappingArray.ToList().IndexOf(x)), x.target});
            CsvDelimiter = item.CsvDelimiter;
            CsvSkipCount = item.CsvSkipCount;
            DataSourceUploadType = (int)item.DataSourceUploadType;
        }


        /// <summary>
        /// Method for creating a view model for editing a data source
        /// </summary>
        /// <param name="item">item</param>
        /// <returns></returns>
        public static DataSourceEditVm Create(DataSource item) => new DataSourceEditVm(item);

        public string Name { get; }
        public string Description { get; }
        public int Priority { get; }
        public int AllowedOperations { get; }
        public IEnumerable<string> AttributesToCheck { get; }
        public IEnumerable<string> OriginalCsvAttributes { get; }
        public int StatUnitType { get; }
        public string Restrictions { get; }
        public IEnumerable<string[]> VariablesMapping { get; }
        public string CsvDelimiter { get; }
        public int CsvSkipCount { get; }
        public int DataSourceUploadType { get; set; }

    }
}
