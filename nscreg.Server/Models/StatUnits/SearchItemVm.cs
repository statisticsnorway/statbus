using System;
using Newtonsoft.Json.Linq;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Utilities;

namespace nscreg.Server.Models.StatUnits
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class SearchItemVm
    {
        public static object Create<T>(T statUnit, StatUnitTypes type, HashSet<string> propNames)
        {
            return DataAccessResolver.Execute(statUnit, propNames, jo =>
            {
                jo.Add("type", (int) type);
            });
        }
    }
}
