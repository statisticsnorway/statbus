using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities
{
    public interface IModelWithId
    {
        int Id { get; set; }
    }
}
