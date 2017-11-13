using Newtonsoft.Json.Linq;

namespace nscreg.Utilities
{
    public static class JsonPathHelper
    {
        /// <summary>
        /// Replace/update JSON string value by path (array index handling in path is not implemented)
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="jsonString"></param>
        /// <param name="dotSeparatedPath"></param>
        /// <param name="targetValue"></param>
        /// <returns></returns>
        public static string ReplacePath<T>(string jsonString, string dotSeparatedPath, T targetValue)
        {
            // https://stackoverflow.com/questions/35799010/editing-json-using-jsonpath
            // https://stackoverflow.com/questions/33828942/set-json-attribute-by-path
            var root = JToken.Parse(jsonString);
            var value = JToken.FromObject(targetValue);
            var pathArray = dotSeparatedPath.Split('.');
            for (var i = pathArray.Length - 1; i >= 0; i--)
            {
                var token = root.SelectToken($@"$.{string.Join(".", pathArray, 0, i + 1)}");
                if (token != null)
                {
                    token.Replace(value);
                    break;
                }
                var newRoot = JToken.Parse($@"{{'{pathArray[i]}':''}}");
                newRoot.SelectToken($@"$.{pathArray[i]}").Replace(value);
                if (i > 0) value = newRoot;
                else root = newRoot;
            }
            return root.ToString();
        }
    }
}
