using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class DataSourceLogsController: Controller
    {
        public DataSourceLogsController(NSCRegDbContext ctx)
        {
            
        }
    }
}
