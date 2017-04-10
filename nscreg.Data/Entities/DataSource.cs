using nscreg.Data.Constants;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    public class DataSource
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public SourcePriority Priority { get; set; }
        public DataSourceAllowedOperation AllowedOperations { get; set; }
        public string AttributesToCheck { get; set; }
        public string Restrictions { get; set; }
        public string VariablesMapping { get; set; }

        [NotMapped]
        public IEnumerable<string> AttributesToCheckArray
        {
            get
            {
                return string.IsNullOrEmpty(AttributesToCheck)
                    ? Enumerable.Empty<string>()
                    : AttributesToCheck.Split(',');
            }
            set { AttributesToCheck = string.Join(",", value ?? Enumerable.Empty<string>()); }
        }
    }
}
