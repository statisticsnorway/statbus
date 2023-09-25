using System;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.AspNetCore.Identity;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  User entity class
    /// </summary>
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

        public DateTimeOffset CreationDate { get; set; } = DateTimeOffset.UtcNow;
        public DateTimeOffset? SuspensionDate { get; set; }
        public virtual ICollection<DataSource> DataSources { get; set; }
        public virtual ICollection<DataSourceQueue> DataSourceQueues { get; set; }
        public virtual ICollection<UserRegion> UserRegions { get; set; } = new HashSet<UserRegion>();
        public virtual ICollection<AnalysisQueue> AnalysisQueues { get; set; }
        public virtual ICollection<SampleFrame> SampleFrames { get; set; }
        public virtual ICollection<UserRole> UserRoles { get; set; }
        public virtual ICollection<ActivityCategoryUser> ActivityCategoryUsers { get; set; } =
            new HashSet<ActivityCategoryUser>();
    }
}
