using Microsoft.AspNetCore.Mvc;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Reflection;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccessAttributesController : Controller
    {
        public IActionResult SystemFunctions()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var item in Enum.GetValues(typeof(SystemFunction)))
                arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
            return Ok(arr);
        }

        public IActionResult DataAttributes()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var prop in typeof(StatisticalUnit).GetProperties())
                arr.Add(new KeyValuePair<int, string>(arr.Count, prop.Name));
            return Ok(arr);
        }
    }
}
