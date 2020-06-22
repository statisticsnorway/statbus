using System;
using nscreg.Data.Constants;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity data source
    /// </summary>
    public class DataSource
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string UserId { get; set; }
        public DataSourcePriority Priority { get; set; }
        public DataSourceAllowedOperation AllowedOperations { get; set; }
        public string AttributesToCheck { get; set; }
        public string OriginalCsvAttributes { get; set; }
        public StatUnitTypes StatUnitType { get; set; }
        public string Restrictions { get; set; }
        public string VariablesMapping { get; set; }
        public string CsvDelimiter { get; set; }
        public int CsvSkipCount { get; set; }
        public DataSourceUploadTypes DataSourceUploadType { get; set; }


        public virtual ICollection<DataSourceQueue> DataSourceQueuedUploads { get; set; }
        public virtual User User { get; set; }


        [NotMapped]
        public IEnumerable<string> AttributesToCheckArray
        {
            get => string.IsNullOrEmpty(AttributesToCheck)
                ? Enumerable.Empty<string>()
                : AttributesToCheck.Split(',');
            set => AttributesToCheck = string.Join(",", value ?? Enumerable.Empty<string>());
        }
        [NotMapped]
        public IEnumerable<string> OriginalAttributesArray
        {
            get => string.IsNullOrEmpty(OriginalCsvAttributes)
                ? Enumerable.Empty<string>()
                : OriginalCsvAttributes.Split(',');
            set => OriginalCsvAttributes = string.Join(",", value ?? Enumerable.Empty<string>());
        }

        [NotMapped]
        public (string source, string target)[] VariablesMappingArray =>
            VariablesMapping?.Split(',').Select(vm =>
            {
                var pair = vm.Split('-');
                return (pair[0], pair[1]);
            }).ToArray()
            ?? Array.Empty<(string, string)>();
    }
}
