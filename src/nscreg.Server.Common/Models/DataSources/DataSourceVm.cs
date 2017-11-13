using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// Вью модель источника данных
    /// </summary>
    public class DataSourceVm
    {
        private DataSourceVm(DataSource item)
        {
            Id = item.Id;
            Name = item.Name;
            Description = item.Description;
            Priority = (int) item.Priority;
            AllowedOperations = (int) item.AllowedOperations;
            AttributesToCheck = item.AttributesToCheckArray;
            StatUnitType = (int) item.StatUnitType;
            Restrictions = item.Restrictions;
            VariablesMapping = item.VariablesMapping;
            CsvDelimiter = item.CsvDelimiter;
            CsvSkipCount = item.CsvSkipCount;
        }
        
        /// <summary>
        /// Метод создания вью модели источника данных
        /// </summary>
        /// <param name="item">Единица</param>
        /// <returns></returns>
        public static DataSourceVm Create(DataSource item) => new DataSourceVm(item);

        public int Id { get; }
        public string Name { get; }
        public string Description { get; }
        public int Priority { get; }
        public int AllowedOperations { get; }
        public IEnumerable<string> AttributesToCheck { get; }
        public int StatUnitType { get; set; }
        public string Restrictions { get; }
        public string VariablesMapping { get; }
        public string CsvDelimiter { get; }
        public int CsvSkipCount { get; }
    }
}
