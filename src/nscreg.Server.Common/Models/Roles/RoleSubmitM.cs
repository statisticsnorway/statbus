using System.Collections.Generic;
using FluentValidation;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Models.Roles
{
    /// <summary>
    /// Role Dispatch Model
    /// </summary>
    public class RoleSubmitM
    {
        public string Name { get; set; }

        public string Description { get; set; }

        public IEnumerable<int> AccessToSystemFunctions { get; set; }

        public DataAccessModel StandardDataAccess { get; set; }
        public IEnumerable<int> ActivityCategoryIds { get; set; }
        public string SqlWalletUser { get; set; }
    }

    /// <summary>
    /// Role Dispatch Validation Model
    /// </summary>
    public class RoleSubmitMValidator : AbstractValidator<RoleSubmitM>
    {
        public RoleSubmitMValidator()
        {
            RuleFor(x => x.Name).NotNull().NotEmpty();
            RuleFor(x => x.AccessToSystemFunctions).NotNull().NotEmpty();
        }
    }
}
