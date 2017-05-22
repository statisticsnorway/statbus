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
        public DataSourcePriority Priority { get; set; }
        public DataSourceAllowedOperation AllowedOperations { get; set; }
        public string AttributesToCheck { get; set; }
        public int StatUnitType { get; set; }
        public string Restrictions { get; set; }
        public string VariablesMapping { get; set; }
        public virtual ICollection<DataSourceQueue> DataSourceLogs { get; set; }
        public string UserId { get; set; }
        public virtual User User { get; set; }

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
