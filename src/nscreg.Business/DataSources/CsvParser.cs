using ServiceStack;
using System.Collections.Generic;
using System.Linq;
using ServiceStack.Text;

namespace nscreg.Business.DataSources
{
    public static class CsvParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, object>> GetParsedEntities(string rawLines, string delimiter)
        {
            CsvConfig.ItemSeperatorString = delimiter;
            var listFields = rawLines.Split('\r', '\n').FirstOrDefault().Split(delimiter);
            var nestedList = listFields.Select(x => new { Key = x, Names = x.Split('.') }).Where(f => f.Names.Length > 1).ToDictionary(x => x.Key, y => y.Names);
            var rowsFromCsv = rawLines.FromCsv<List<Dictionary<string, string>>>();
            var resultDictionary = new List<Dictionary<string, object>>();
            for (int j = 0; j < rowsFromCsv.Count; j++)
            {
                //int countNull = rowsFromCsv[j].Where(u => !nestedList.ContainsKey(u.Key)).Count(x => x.Value == null);
                //if (nestedList.Count == 0 || countNull == 0)
                //{
                    var activity = rowsFromCsv[j].Where(u => nestedList.ContainsKey(u.Key)).ToDictionary(x => x.Key, y => (object)y.Value);
                    var unit = rowsFromCsv[j].Where(u => !nestedList.ContainsKey(u.Key) && u.Value != null).ToDictionary(x => x.Key, y => (object)y.Value);
                    foreach (var nestedElement in nestedList.Select(x => string.Join(".", x.Value.Take(2))).Distinct())
                    {
                        var nestedElementAsArray = nestedElement.Split('.');
                        var firstLevelName = nestedElementAsArray[0];
                        var secondLevelName = nestedElementAsArray[1];
                        var a = activity.Where(x => x.Key.StartsWith(firstLevelName)).ToDictionary(x => x.Key.Split('.').Last(), y => (string)y.Value);
                        var b = new KeyValuePair<string, Dictionary<string, string>>(secondLevelName, a);
                        unit[firstLevelName] = new List<KeyValuePair<string, Dictionary<string, string>>>(new[] { b });
                    }

                    var dictItem = resultDictionary.FirstOrDefault(d =>
                        d["StatId"].ToString() == unit["StatId"].ToString() || d["TaxId"].ToString() == unit["TaxId"].ToString() || d["ExternalId"].ToString() == unit["ExternalId"].ToString());

                    if (dictItem != null)
                    {
                        if (dictItem.ContainsKey("Activities"))
                        {
                            if((unit["Activities"] as List<KeyValuePair<string, Dictionary<string, string>>>).Any(c => c.Value.Values.Any(x => x != null)))
                                (dictItem["Activities"] as List<KeyValuePair<string, Dictionary<string, string>>>)?.AddRange(
                                    (List<KeyValuePair<string, Dictionary<string, string>>>) unit["Activities"]);
                        }

                        if (dictItem.ContainsKey("Persons"))
                        {
                            if((unit["Persons"] as List<KeyValuePair<string, Dictionary<string, string>>>).Any(c => c.Value.Values.Any(x => x != null)))
                                (dictItem["Persons"] as List<KeyValuePair<string, Dictionary<string, string>>>)?.AddRange(
                                    (List<KeyValuePair<string, Dictionary<string, string>>>)unit["Persons"]);
                        }
                    }
                    else
                    {
                        resultDictionary.Add(unit);
                    }
                    
                //}
                //else
                //{
                //    var activity = rowsFromCsv[j].Where(u => nestedList.ContainsKey(u.Key)).ToList().ToDictionary(x => x.Key, y => (object)y.Value);
                //    foreach (var nestedElement in nestedList.Select(x => string.Join(".", x.Value.Take(2))).Distinct())
                //    {
                //        var nestedElementAsArray = nestedElement.Split('.').ToArray();
                //        var a = activity.Where(x => x.Key.StartsWith(nestedElementAsArray[0]) && x.Value != null).ToDictionary(x => x.Key.Split('.').Last(), y => (string)y.Value);
                //        if (a.Count() != 0)
                //        {
                //            var num = resultDictionary.Count - 1;
                //            (resultDictionary[num][nestedElementAsArray[0]] as List<KeyValuePair<string, Dictionary<string, string>>>)?.Add(new KeyValuePair<string, Dictionary<string, string>>(nestedElementAsArray[1], a));
                //        }
                //    }
                //}
            }
            return resultDictionary;
        }
    }
}
