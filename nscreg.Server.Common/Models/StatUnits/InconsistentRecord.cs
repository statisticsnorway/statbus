using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class InconsistentRecord
    {
        public InconsistentRecord(int regId, StatUnitTypes type, string name, List<string> inconsistents)
        {
            RegId = regId;
            Type = type;
            Name = name;
            Inconsistents = inconsistents;
        }

        public InconsistentRecord(int regId, StatUnitTypes type, string name, string inconsistents)
        {
            RegId = regId;
            Type = type;
            Name = name;
            Inconsistents = inconsistents.Split(';').ToList();
        }

        public int RegId { get; }
        public StatUnitTypes Type { get; }
        public string Name { get; }
        public List<string> Inconsistents { get; }
    }
}