using Microsoft.AspNetCore.Mvc;
using nscreg.Data.Constants;
using System;
using System.Collections.Generic;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccessAttributesController : Controller
    {
        public IActionResult SystemFunctions()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var item in Enum.GetValues(typeof(SystemFunction)))
            {
                arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
            }
            return Ok(arr);
        }

        public IActionResult DataAttributes()
        {
            var arr = new KeyValuePair<int, string>[]
            {
                new KeyValuePair<int, string>(1, "Name"),
                new KeyValuePair<int, string>(2, "Phone"),
            };
            return Ok(arr);
        }
    }
}
