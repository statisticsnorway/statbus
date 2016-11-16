using System;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data.Entities;
using Microsoft.AspNetCore.Authorization;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccessAttributesController : Controller
    {
        [AllowAnonymous]
        public IActionResult SystemFunctions()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var item in Enum.GetValues(typeof(SystemFunction)))
            {
                arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
            }
            return Ok(arr);
        }
    }
}
