using System.Collections.Generic;
using FluentValidation;
using nscreg.Data.Entities;
using nscreg.Server.Models.DataAccess;

namespace nscreg.Server.Models.Roles
{
    public class RoleSubmitM
    {
        public string Name { get; set; }

        public string Description { get; set; }

        public IEnumerable<int> AccessToSystemFunctions { get; set; }

        public DataAccessModel StandardDataAccess { get; set; }
        public Region Region { get; set;  }
        public ActivityCategory Activity { get; set; }
    }

    public class RoleSubmitMValidator : AbstractValidator<RoleSubmitM>
    {
        public RoleSubmitMValidator()
        {
            RuleFor(x => x.Name).NotNull().NotEmpty();
            RuleFor(x => x.AccessToSystemFunctions).NotNull().NotEmpty();
            RuleFor(x => x.Region.Id).NotNull().NotEmpty().GreaterThan(0);
            RuleFor(x => x.Activity.Id).NotNull().NotEmpty().GreaterThan(0);
        }
    }
}
