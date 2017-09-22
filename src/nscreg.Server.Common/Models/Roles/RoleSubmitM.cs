using System.Collections.Generic;
using FluentValidation;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Models.Roles
{
    /// <summary>
    /// Модель отправки роли
    /// </summary>
    public class RoleSubmitM
    {
        public string Name { get; set; }

        public string Description { get; set; }

        public IEnumerable<int> AccessToSystemFunctions { get; set; }

        public DataAccessModel StandardDataAccess { get; set; }
        public IEnumerable<int> ActiviyCategoryIds { get; set; }
    }

    /// <summary>
    /// Модель валидации отправки роли
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
