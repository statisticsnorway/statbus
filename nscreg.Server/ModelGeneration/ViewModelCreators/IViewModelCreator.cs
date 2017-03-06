using System.Collections.Generic;
using nscreg.Server.Models.Infrastructure;

namespace nscreg.Server.ModelGeneration.ViewModelCreators
{
    public interface IViewModelCreator<in T>
    {
        ViewModelBase Create(T domainEntity, HashSet<string> propNames);
    }
}