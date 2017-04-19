using nscreg.Data.Entities;
using System.Collections.Generic;

namespace nscreg.Server.Models.DataSources
{
    public class DataSourceVm
    {
        private DataSourceVm(DataSource item)
        {
            Id = item.Id;
            Name = item.Name;
            Description = item.Description;
            Priority = (int)item.Priority;
            AllowedOperations = (int)item.AllowedOperations;
            AttributesToCheck = item.AttributesToCheckArray;
            Restrictions = item.Restrictions;
            VariablesMapping = item.VariablesMapping;
        }

        public static DataSourceVm Create(DataSource item) => new DataSourceVm(item);

        public int Id { get; }
        public string Name { get; }
        public string Description { get; }
        public int Priority { get; }
        public int AllowedOperations { get; }
        public IEnumerable<string> AttributesToCheck { get; }
        public string Restrictions { get; }
        public string VariablesMapping { get; }
    }
}
