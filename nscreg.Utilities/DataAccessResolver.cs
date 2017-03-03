using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Utilities.Classes;
using Newtonsoft.Json.Linq;

namespace nscreg.Utilities
{
    internal static class DataAccessResolver<T>
    {
        private static readonly Dictionary<string, DataProperty<T>> Properties
            = typeof(T).GetProperties().ToDictionary(v => v.Name, v => new DataProperty<T>(v));

        public static object Execute(T obj, HashSet<string> propNames, Action<JObject> postProcessor)
        {
            var jo = new JObject();
            foreach (var property in Properties)
            {
                if (propNames.Contains(property.Key) && property.Value.Getter != null)
                {
                    jo.Add(property.Key.LowerFirstLetter(), JToken.FromObject(property.Value.Getter(obj)));
                }
            }
            postProcessor?.Invoke(jo);
            return jo.ToObject<object>();
        }
    }

    //TODO: Replace Action<JObject> to Extend with object
    public static class DataAccessResolver
    {
        private static readonly MethodInfo DataAccessExecute =
            typeof(DataAccessResolver).GetMethod(nameof(DataAccessResolver.Execute));

        public static object Execute(object obj, HashSet<string> propNames, Action<JObject> postProcessor)
        {
            var generic = DataAccessExecute.MakeGenericMethod(obj.GetType());
            return (string) generic.Invoke(null, new[] {obj, propNames, postProcessor });
        }

        public static object Execute<T>(T obj, HashSet<string> propNames, Action<JObject> postProcessor)
        {
            if (obj.GetType() != typeof(T))
            {
                return Execute(obj, propNames, postProcessor);
            }
            return DataAccessResolver<T>.Execute(obj, propNames, postProcessor);
        }
    }
}