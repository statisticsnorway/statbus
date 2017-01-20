namespace nscreg.Server.Models.Dynamic.Property
{
    public class IntegerPropertyMetadata : PropertyMetadataBase
    {
        public IntegerPropertyMetadata(string name, bool isRequired, int? value) : base(name, isRequired)
        {
            Value = value;
        }

        public int? Value { get; set; }
        public override PropertyType Selector => PropertyType.Integer;

    }
}