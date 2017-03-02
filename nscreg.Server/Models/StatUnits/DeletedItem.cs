namespace nscreg.Server.Models.StatUnits
{
    public class DeletedItem
    {
        private DeletedItem(int regId, int type, string name)
        {
            RegId = regId;
            Type = type;
            Name = name;
        }

        internal static DeletedItem Create(int regId, int type, string name) => new DeletedItem(regId, type, name);

        public int RegId { get; }
        public int Type { get; }
        public string Name { get; }
    }
}
