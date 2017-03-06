using nscreg.Data.Constants;

namespace nscreg.Server.Models.StatUnits
{
    public class DeletedItem
    {
        private DeletedItem(int regId, StatUnitTypes type, string name)
        {
            RegId = regId;
            Type = type;
            Name = name;
        }

        internal static DeletedItem Create(int regId, StatUnitTypes type, string name)
            => new DeletedItem(regId, type, name);

        public int RegId { get; }
        public StatUnitTypes Type { get; }
        public string Name { get; }
    }
}
