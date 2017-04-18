using System;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;

namespace nscreg.Data.Entities
{
    public class User : IdentityUser
    {
        [NotMapped]
        public string Login
        {
            get { return UserName; }
            set
            {
                UserName = value;
                NormalizedUserName = value.ToUpper();
            }
        }

        public string Name { get; set; }
        public string Description { get; set; }
        public UserStatuses Status { get; set; }
        public string DataAccess { get; set; }

        [NotMapped]
        public IEnumerable<string> DataAccessArray
        {
            get
            {
                return string.IsNullOrEmpty(DataAccess)
                    ? new string[0]
                    : DataAccess.Split(',');
            }
            set
            {
                DataAccess = string.Join(",", value);
            }
        }

        public int? RegionId { get; set; }
        public virtual Region Region { get; set; }

        public DateTime CreationDate { get; set; } = DateTime.Now;
        public DateTime? SuspensionDate { get; set; }
        public virtual ICollection<DataSource> DataSources { get; set; }
        public virtual ICollection<DataSourceQueue> DataSourceQueues { get; set; }
    }
}
