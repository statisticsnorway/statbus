using ServiceStack;
using System.Collections.Generic;
using System.Linq;
using nscreg.Utilities.Extensions;
using ServiceStack.Text;

namespace nscreg.Business.DataSources
{
    public static class CsvParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, object>> GetParsedEntities(string rawLines, string delimiter, (string source, string target)[] variableMappingsArray)
        {
            CsvConfig.ItemSeperatorString = delimiter;
            var csvHeaders = rawLines.Split(new []{'\r', '\n'}, 2).First().Split(delimiter);
            var rowsFromCsv = rawLines.FromCsv<List<Dictionary<string, string>>>();
            var resultDictionary = new List<Dictionary<string, object>>();
            var arrayConst = new[] { "Activities", "Persons", "ForeignParticipationCountriesUnits" };
            for (var j = 0; j < rowsFromCsv.Count;)
            {
                // Transform to array (target, value) according to mapping
                var unit = rowsFromCsv[j].Where(z => z.Value.HasValue()).Join(variableMappingsArray, r => r.Key, m => m.source,
                    (r, m) =>  new KeyValuePair<string, object>(m.target, r.Value));

                var unitResult = new Dictionary<string, object>();
                foreach (var keyValue in unit)
                {
                    // keySplitted[0] = one of the value arrayConst
                    // keySplitted[1] = Activity, Person or ForeignParticipationCountry
                    // keySplitted[2] = one of the value in keySplitted[1]

                    var keySplitted = keyValue.Key.Split('.');
                    if (keySplitted.Length == 1 && !arrayConst.Contains(keySplitted[0]))
                        unitResult.Add(keyValue.Key, keyValue.Value);

                    List<KeyValuePair<string, Dictionary<string, string>>> arrayProperty = null;
                    if (!unitResult.TryGetValue(keySplitted[0], out object obj))
                    {
                        obj = new List<KeyValuePair<string, Dictionary<string, string>>>()
                        {
                            new KeyValuePair<string, Dictionary<string, string>>(keySplitted[1], new Dictionary<string, string>())
                        };
                        unitResult.Add(keySplitted[0], obj);
                    }

                    arrayProperty = obj as List<KeyValuePair<string, Dictionary<string, string>>>;

                    if (arrayProperty != null)
                        arrayProperty[0].Value[keySplitted.Last()] = keyValue.Value.ToString();

                }

                //var unit = rowsFromCsv[j].Where(u => variableMappingsArray.All(z => z.source != u.Key) && u.Value != null).ToDictionary(x => x.Key, y => (object)y.Value);

                //foreach (var nestedElement in nestedList.Select(x => string.Join(".", x.Value.Take(2))).Distinct())
                //{
                //    var nestedElementAsArray = nestedElement.Split('.');
                //    var firstLevelName = nestedElementAsArray[0];
                //    var secondLevelName = nestedElementAsArray[1];
                //    var a = activity.Where(x => x.Key.StartsWith(firstLevelName)).ToDictionary(x => x.Key.Split('.').Last(), y => (string)y.Value);
                //    var b = new KeyValuePair<string, Dictionary<string, string>>(secondLevelName, a);
                //    //unit[firstLevelName] = new List<KeyValuePair<string, Dictionary<string, string>>>(new[] { b });
                //}

                var dictItem = new Dictionary<string, object>();
                object unitValue;
                object dictValue = null;

                //if (unit.TryGetValue("ExternalId", out unitValue))
                //{
                //    if (resultDictionary.LastOrDefault(c => c.TryGetValue("ExternalId", out dictValue)) != null)
                //    {
                //        dictItem = resultDictionary.LastOrDefault(d => unitValue.ToString() == dictValue.ToString());
                //    }

                //}
                //if (unit.TryGetValue("TaxId", out unitValue))
                //{
                //    if (resultDictionary.LastOrDefault(c => c.TryGetValue("TaxId", out dictValue)) != null)
                //    {
                //        dictItem = resultDictionary.LastOrDefault(d => unitValue.ToString() == dictValue.ToString());
                //    }

                //}
                //if (unit.TryGetValue("StatId", out unitValue))
                //{
                //    if (resultDictionary.LastOrDefault(c => c.TryGetValue("StatId", out dictValue)) != null)
                //    {
                //        dictItem = resultDictionary.LastOrDefault(d => dictValue.ToString() == unitValue.ToString());
                //    }

                //}

                //if (dictItem != null && dictItem.Any())
                //{
                //    if (dictItem.ContainsKey("Activities"))
                //    {
                //        if ((unit["Activities"] as List<KeyValuePair<string, Dictionary<string, string>>>).Any(c => c.Value.Values.Any(x => x != null)))
                //            (dictItem["Activities"] as List<KeyValuePair<string, Dictionary<string, string>>>)?.AddRange(
                //                (List<KeyValuePair<string, Dictionary<string, string>>>)unit["Activities"]);
                //    }

                //    if (dictItem.ContainsKey("Persons"))
                //    {
                //        if ((unit["Persons"] as List<KeyValuePair<string, Dictionary<string, string>>>).Any(c => c.Value.Values.Any(x => x != null)))
                //            (dictItem["Persons"] as List<KeyValuePair<string, Dictionary<string, string>>>)?.AddRange(
                //                (List<KeyValuePair<string, Dictionary<string, string>>>)unit["Persons"]);
                //    }
                //}
                //else
                //{
                //    resultDictionary.Add(unit);
                //}
            }
            return resultDictionary;
        }
    }
}
